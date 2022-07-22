using SystemImageLoader
using Test
using TOML

@testset "SystemImageLoader" begin
    @test isfile(SystemImageLoader.system_image_loader())
    @test success(`$(SystemImageLoader.system_image_loader()) --help`)

    image, = splitext(unsafe_string(Base.JLOptions().image_file))
    depot = first(Base.DEPOT_PATH)
    config = Config(; image, depot)

    @test isfile(config.image)
    @test isdir(config.depot)

    buffer = IOBuffer()
    SystemImageLoader.toml(config; stdout=buffer)
    toml = TOML.parse(String(take!(buffer)))

    @test length(toml) == 2
    @test isfile(toml["image"])
    @test !isempty(toml["depot"])
end
