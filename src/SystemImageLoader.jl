module SystemImageLoader

#
# Imports:
#

using Artifacts
import TOML
import LazyArtifacts
import REPL.TerminalMenus

#
# Exports:
#

export @ArtifactInstaller, ArtifactConfig, @artifact_str, LazyArtifacts

export Config

export link, remove

#
# Provider Interface:
#

struct ArtifactInstaller
    lookup::Function
    names::Vector{String}
end

function Base.show(io::IO, a::ArtifactInstaller)
    print(io, "$ArtifactInstaller(", repr(a.names), ")")
end

function (installer::ArtifactInstaller)()
    if isinteractive()
        @info "pick the system images you would like to install."
        names = installer.names
        menu = TerminalMenus.MultiSelectMenu(names)
        for index in TerminalMenus.request(menu)
            name = names[index]
            @info "installing `$name` system image."
            installer.lookup(name)
            @info "finished installing `$name` system image."
        end
    else
        error("cannot use interactive installer in non-interactive Julia session.")
    end
end
(installer::ArtifactInstaller)(name::AbstractString) = installer.lookup(name)

"""
Defines an interactive artifact installer that the user can run to select the
artifacts that they would like to install locally.

```julia
module MySystemImageProvider

using SystemImageLoader

const install = @ArtifactInstaller "../Artifacts.toml"

end
```

Users can then either call `MySystemImageProvider.install()` to get an
interactive prompt to select the available images for installation, or run
`MySystemImageProvider.install("NameOfImage")` for non-interactive use.
"""
macro ArtifactInstaller(artifacts...)
    names = collect(map(artifacts) do x
        if Meta.isexpr(x, :macrocall, 3)
            if x.args[1] === Symbol("@artifact_str")
                return x.args[3]
            end
        end
        error("invalid macro call")
    end)
    expr = Expr(:block)
    for (name, artifact) in zip(names, artifacts)
        push!(expr.args, :(name == $name && return $artifact))
    end
    push!(expr.args, :(error("not a valid artifact: `$name`.")))
    return esc(:($(ArtifactInstaller)((name) -> $expr, $names)))
end

const __installer = @ArtifactInstaller(
    artifact"system-image-loader"
)

struct ArtifactConfig
    installer::ArtifactInstaller
end

const __config = ArtifactConfig(__installer)

Base.show(io::IO, a::ArtifactConfig) = print(io, "$ArtifactConfig($(repr(a.installer.names))")

function (config::ArtifactConfig)(name::Symbol)
    name = String(name)
    depot = config.installer.lookup(name)
    image = joinpath(depot, "system-images", "$name")
    return Config(; image, depot)
end

#
# Artifacts:
#

const BIN_EXTENSION = Sys.iswindows() ? ".exe" : ""

system_image_loader() = joinpath(artifact"system-image-loader", "system-image-loader$BIN_EXTENSION")

#
# `juliaup` helpers for creating linked channels that point to the right places.
#

function link(package::Module, image::Symbol)
    channel = channel_name(package, image)
    julia = VERSION # TODO: maybe not hardcoded.
    launcher = system_image_loader()
    # Create the link for juliaup to be able to launch this channel. The trailing `--` is needed
    # to allow passing extra arguments to the launched julia process.
    run(`juliaup link $channel $launcher -- --julia=$julia --package=$package --image=$image --`)
end

function remove(package::Module, image::Symbol)
    channel = channel_name(package, image)
    run(`juliaup remove $channel`)
end

channel_name(package::Module, image::Symbol) = "$VERSION/$(nameof(package))/$image"

#
# Config:
#

const SYSIMAGE_EXTENSION = Sys.iswindows() ? "dll" : Sys.isapple() ? "dylib" : "so"

struct Config
    image::String
    depot::String

    function Config(; image::AbstractString, depot::AbstractString)
        image = "$image.$SYSIMAGE_EXTENSION"
        isfile(image) || error("not a valid system image file name: $image")
        isdir(depot) || error("not a valid julia depot folder name: $depot")
        return new(image, depot)
    end
end

"""
A local system image loader. It expects to find a `system-image-loader` key in
the `Project.toml` file with entries containing `image` (and optionally
`depot`) key/value pairs, e.g

```toml
[system-image-loader.Custom]
image = "path/to/image" # No file extension.
depot = "path/to/depot" # Optional. Default depot gets used if not provided.

# More than one image can be provided.
[system-image-loader.OtherImage]
image = "..."
```
"""
function config(name::Symbol; dir=pwd())::Config
    directory, table = get_loader_section_from_project(dir)
    section = get(Dict{String,Any}, table, String(name))

    depot = get(section, "depot") do
        get(Base.DEPOT_PATH, 1, nothing)
    end
    if isnothing(depot)
        error("could not find a `depot` to use.")
    end
    depot = abs_path_expand(depot, directory)

    image = get(section, "image", nothing)
    if isnothing(image)
        globals = joinpath(depot, "system-images")
        if safe(isdir, globals)
            image = joinpath(globals, String(name))
        else
            error("could not find an `image` named `$name` to use.")
        end
    end
    image = abs_path_expand(image, directory)

    return Config(; image, depot)
end

function get_loader_section_from_project(dir::String)
    DICT = Dict{String,Any}
    if safe(isdir, dir)
        for each in Base.project_names
            file = joinpath(dir, each)
            if safe(isfile, file)
                toml = try_parse_toml(file)
                table = get(toml, "system-image-loader", nothing)
                if isnothing(table)
                    continue
                else
                    return (dir, isa(table, DICT) ? table : DICT())
                end
            end
        end
        if dir == homedir()
            return (dir, DICT())
        else
            parent = dirname(dir)
            if parent == dir
                return (dir, DICT())
            else
                return get_loader_section_from_project(dirname(dir))
            end
        end
    else
        return (dir, DICT())
    end
end

function try_parse_toml(file::String)
    try
        TOML.parsefile(file)
    catch exception
        @debug "failed to parse TOML file" exception
        Dict{String,Any}()
    end
end

function safe(f, args...)
    try
        f(args...)
    catch err
        err isa Base.IOError || rethrow()
        false
    end
end

function abs_path_expand(path::String, project_directory::String)
    path = expanduser(path)
    if isabspath(path)
        return path
    else
        abspath(normpath(joinpath(project_directory, path)))
    end
end

const PATH_SEPARATOR = Sys.iswindows() ? ';' : ':'

function toml(config::Config; stdout=stdout)
    image = config.image
    depot = config.depot

    # Insert the provided depot after the user's main one since this provided
    # depot is readonly and we don't want it to override stuff the user already
    # has. Drop duplicate entries to avoid double lookups.
    depot_path = unique!(insert!(copy(Base.DEPOT_PATH), 2, depot))
    depot_path_expanded = join(depot_path, PATH_SEPARATOR)

    # Write to simple TOML format. We don't need `TOML.jl` since we're only
    # using basic values. The rust side of things uses a TOML parser though.
    println(stdout, "image = ", repr(image))
    println(stdout, "depot = ", repr(depot_path_expanded))
end
toml(@nospecialize(value); stdout=stdout) = println(stdout, "")

end # module
