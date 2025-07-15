package game

import "core:log"
import sdl "vendor:sdl3"

passthrough_vert := #load("../assets/shaders/passthrough.spv.vert")
fullbright_frag := #load("../assets/shaders/fullbright.spv.frag")

RenderData :: struct {
	window: ^sdl.Window, // Pointer to the SDL window.
	renderer : ^sdl.Renderer, // Pointer to the SDL renderer.
	gpu : ^sdl.GPUDevice, // Pointer to the SDL renderer.
	pipeline : ^sdl.GPUGraphicsPipeline, // Pointer to the GPU pipeline.
	tri_vertex_buffer: ^sdl.GPUBuffer, // GPU buffer for triangle vertices.
} 

UBO :: struct {
    mvp: matrix[4,4]f32, // Projection matrix.
}

Vertex :: struct {
	loc: V3f, // Vertex position.
	color: Colorf, // Vertex color.
}

triangle_verts :: []Vertex {
	{loc = {-0.5, -0.5, 0}, color = {1, 0, 0}},
	{loc = {0, 0.5, 0}, color = {0, 1, 0}},
	{loc = {0.5, -0.5, 0}, color = {0, 0, 1}},
}

tri_byte_size :: proc() -> u32 {
	return u32(len(triangle_verts) * size_of(triangle_verts[0]))
}

quad_verts :: []V3f {
	{-0.5, -0.5, 0},
	{0.5, -0.5, 0},
	{0.5, 0.5, 0},
	{-0.5, 0.5, 0},
}

load_shader :: proc(code : []u8, stage : sdl.GPUShaderStage, num_ubos: u32) -> ^sdl.GPUShader {
	if len(code) == 0 {
		log.errorf("Shader code is empty!")
		return nil
	}

	shader := sdl.CreateGPUShader(g.r.gpu, {
		code_size = len(code),
		code = raw_data(code),
		entrypoint = "main",
		format = {.SPIRV},
		stage = stage,
		num_uniform_buffers = num_ubos,
	})

	if shader == nil {
		log.errorf("Failed to create GPU shader! %s", sdl.GetError())
		return nil
	}

	return shader
}
