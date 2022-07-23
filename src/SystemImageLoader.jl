module SystemImageLoader

#
# Exports:
#

export Config

export link, remove

#
# Imports:
#

using Artifacts, TOML

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
            return get_loader_section_from_project(dirname(dir))
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
