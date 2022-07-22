import Base.BinaryPlatforms: Platform
import ArtifactUtils

platforms = Dict(
    "i686-unknown-linux-gnu" => Platform("i686", "linux"),
    "x86_64-unknown-linux-gnu" => Platform("x86_64", "linux"),
    "x86_64-apple-darwin" => Platform("x86_64", "macos"),
    "aarch64-apple-darwin" => Platform("aarch64", "macos"),
    "aarch64-unknown-linux-gnu" => Platform("aarch64", "linux"),
    "x86_64-pc-windows-gnu" => Platform("x86_64", "windows"),
)
version = v"1.0.0"
artifact_file = joinpath(@__DIR__, "..", "Artifacts.toml")
url_base = "https://github.com/MichaelHatherly/system-image-loader/releases/download"

for (k, platform) in platforms
    ArtifactUtils.add_artifact!(
        artifact_file,
        "system-image-loader",
        "$(url_base)/v$(version)/system-image-loader-$(version)-$(k).tar.gz";
        platform,
        force = true,
    )
end
