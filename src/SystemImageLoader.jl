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

#
# Provider Interface:
#

struct ArtifactInstaller
    mod::Module
    lookup::Function
    names::Vector{String}
end

function Base.show(io::IO, a::ArtifactInstaller)
    toml = artifact_file(a.mod)
    print(io, "$ArtifactInstaller(\n")
    println(io, "    module: $(a.mod),")
    for each in sort(a.names)
        installed = artifact_installed(toml, each) ? "installed" : "not installed"
        println(io, "    $(repr(each)) = $(repr(installed)),")
    end
    print(io, ")")
end

function (installer::ArtifactInstaller)()
    if isinteractive()
        printstyled("Pick the system images you would like to install.\n"; bold=true, color=:blue)
        names = installer.names
        menu = TerminalMenus.MultiSelectMenu(names)
        selected = String[]
        for index in TerminalMenus.request(menu)
            name = names[index]
            push!(selected, name)
            @info "installing `$name` system image."
            installer.lookup(name)
            @info "finished installing `$name` system image."
        end
        aliases = String[]
        if !isempty(selected)
            println()
            printstyled("Add short names for selected images.\n"; bold=true, color=:blue)
            alias_menu = TerminalMenus.MultiSelectMenu(selected)
            for index in TerminalMenus.request(alias_menu)
                push!(aliases, selected[index])
            end
        end
        cleanup_links(installer.mod, installer.names, selected, aliases)
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
    return esc(:($(ArtifactInstaller)($(__module__), (name) -> $expr, $names)))
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
    image = joinpath(depot, "environments", "$name", "$name")
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

function cleanup_links(version::VersionNumber, mod::Module, images, selected, aliases)
    if !isnothing(Sys.which("juliaup"))
        package = nameof(mod)
        prefix = "$version/$package"
        lines = [line for line in readlines(`juliaup status`) if contains(line, prefix)]
        for image in images
            channel = "$prefix/$image"
            for line in lines
                if contains(line, channel)
                    success(`juliaup remove $channel`)
                end
            end
        end
        toml = artifact_file(mod)
        loader = system_image_loader()
        for image in selected
            if artifact_installed(toml, image)
                channel = "$prefix/$image"
                success(`juliaup link $channel $loader -- --julia=$version --package=$package --image=$image --`) ||
                    @warn "failed to link `$channel`."
            end
        end
        for alias in aliases
            success(`juliaup remove $alias`)
            channel = "$prefix/$alias"
            success(`juliaup link $alias julia $("+$channel")`)
        end
        # Ensure that we actually have the exact channel version required, and
        # not e.g 1.7 instead of 1.7.3.
        success(`juliaup add $("$version")`) ||
            @info "`juliaup` channel `$(version)` already added, skipping."
    else
        @warn "`juliaup` is required for this package to work."
    end
end
cleanup_links(mod::Module, images, selected, aliases) = cleanup_links(VERSION, mod, images, selected, aliases)

function artifact_installed(toml, image)
    sha1 = Artifacts.artifact_hash(image, toml)
    return !isnothing(sha1) && Artifacts.artifact_exists(sha1)
end

function artifact_file(mod::Module)
    return Artifacts.find_artifacts_toml(pkgdir(mod))
end

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

    # Insert a named environment for package lookup. The system image build
    # scripts must generate an environment called `$image` in
    # `.julia/environments/$image` that contains the full Project.toml,
    # Manifest.toml, and optionally `LocalPreferences.toml`. Additionally
    # package sources must be provided in `.julia/packages/`, source content
    # can be discarded, so long as a `Project.toml` and `src/PackageName.jl`
    # exists.
    name = first(splitext(basename(image)))
    load_path = unique!(insert!(copy(Base.LOAD_PATH), 2, "@$name"))
    load_path_expanded = join(load_path, PATH_SEPARATOR)

    # Write to simple TOML format. We don't need `TOML.jl` since we're only
    # using basic values. The rust side of things uses a TOML parser though.
    println(stdout, "image = ", repr(image))
    println(stdout, "depot = ", repr(depot_path_expanded))
    println(stdout, "load_path = ", repr(load_path_expanded))
end
toml(@nospecialize(value); stdout=stdout) = println(stdout, "")

end # module
