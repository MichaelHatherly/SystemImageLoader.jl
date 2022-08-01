# SystemImageLoader.jl

Use Julia's artifact system to ship pre-built system images to users.

## Usage

```julia
module MyCustomImages

using SystemImageLoader

const install = @ArtifactInstaller(
    artifact"MyImage",
)
const config = ArtifactConfig(install)

end
```

Provide an `Artifacts.toml` file in your `MyCustomImages.jl` package that lists
the artifact `MyImage`. The `.tar.gz` must have the following structure:

```
/artifacts
  # All the Julia artifacts required by the system image.
/system-images
  # The system image with the name `ImageOne`.
```

This is a minimal Julia depot folder, with everything not required removed. You
can leave other content in the tarball if you want but this will wastes space
so best practise is to remove the extra folders.

Users of your package can then perform the following steps to install and use your
custom system image:

```
(@v1.7) pkg> add https://github.com/USER_NAME/MyCustomImages.jl

julia> using MyCustomImages

julia> MyCustomImages.install()
```

`install()` will start an interactive prompt to allow the user to pick which
images (if you have several) that they would like to install.

Once installed custom `juliaup` channels will be automatically created for each
available system image.

Starting `julia` with the newly added channel will look like the following:

```
$ julia +1.7.3/MyCustomImages/MyImage
```

where `1.7.3` would be whatever Julia version you installed `MyCustomImages`
with.

If the channel name is too long for your liking then you can alias it to
another shorter channel name with `juliaup` like so:

```
$ juliaup link MyImage julia +1.7.3/MyCustomImages/MyImage
```

which can then be started with just `julia +MyImage`.

# Associated Projects

  - [`system-image-loader`](https://github.com/MichaelHatherly/system-image-loader)
    provides the binary loader used to locate depot and image file paths for a
    given custom channel.

  - [`CuratedSystemImages.jl`](https://github.com/MichaelHatherly/CuratedSystemImages.jl)
    provides a selection of pre-built system images as Julia artifacts that can
    be installed and used as custom channels.

  - [`curated-system-images`](https://github.com/MichaelHatherly/curated-system-images)
    is the builder repository for the above Julia package and is where all the
    project manifests are located for generating specific system image bundles.

