# SystemImageLoader.jl

Ship system images and associated depots via Julia's artifacts system.

## Usage

```julia
module MyCustomImages

#=
Images and depots can be provided however you want, but via the artifact system
is the most straight forward approach. If you have multiple artifacts you may
want to use `lazy` artifacts so that only the ones that are used actually get
downloaded.
=#
using Artifacts

using SystemImageLoader

function config(name::Symbol)
    #=
    `name` can be used to dynamically pick one of several images and depots
    that may be provided by `MyCustomImages`'s `Artifacts.toml` file. This can
    contain any custom logic you need to select the right `image` and `depot`
    paths needed.
    =#

    # The Julia depot to use for the above image.
    depot = artifact"artifact-name"

    # System image to load, without extension appended. Doesn't have to be in
    # the same artifact.
    image = artifact"artifact-name/system-image-name"

    # Must return a `Config` object from `SystemImageLoader`.
    return Config(; image, depot)
end

end
```
