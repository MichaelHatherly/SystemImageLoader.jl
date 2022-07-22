module SystemImageLoader

#
# Exports:
#

export Config

export link, remove

#
# Imports:
#

using Artifacts

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

const SYSIMAGE_EXTENSION = Sys.iswindows() ? "dll" : "so"

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

const PATH_SEPARATOR = Sys.iswindows() ? ';' : ':'

function toml(config::Config; stdout=stdout)
    image = config.image
    depot = config.depot

    # Insert the provided depot after the user's main one since this provided
    # depot is readonly and we don't want it to override stuff the user already
    # has.
    depot_path_expanded = join(insert!(copy(Base.DEPOT_PATH), 2, depot), PATH_SEPARATOR)

    # Write to simple TOML format. We don't need `TOML.jl` since we're only
    # using basic values. The rust side of things uses a TOML parser though.
    println(stdout, "image = ", repr(image))
    println(stdout, "depot = ", repr(depot_path_expanded))
end
toml(@nospecialize(value); stdout=stdout) = println(stdout, "")

end # module
