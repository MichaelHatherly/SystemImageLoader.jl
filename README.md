# SystemImageLoader.jl

Ship system images and associated depots via Julia's artifacts system and load
them via custom `juliaup` channels that handle depot path and sysimage
selection automatically.

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

To load the custom system images on `julia` startup you will need to have
`juliaup` installed and available on your `PATH`.

```
julia> using MyCustomImages, SystemImageLoader

julia> link(MyCustomImages, :MyImage)
```

and then start `julia` with the newly added channel:

```
$ julia +1.7.3/MyCustomImages/MyImage
```

which will find the linked system image and the depot path that contains any
artifacts it may require and then launch `julia` with those set correctly.

If the channel name is too long for you liking then you can alias it to another
shorter channel name with `juliaup` like so:

```
$ juliaup link MyImage julia +1.7.3/MyCustomImages/MyImage
```

which can then be started with just `julia +MyImage`.
