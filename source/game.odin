/*
This file is the starting point of your game.

Some important procedures are:
- game_init_window: Opens the window
- game_init: Sets up the game state
- game_update: Run once per frame
- game_should_close: For stopping your game when close button is pressed
- game_shutdown: Shuts down game and frees memory
- game_shutdown_window: Closes window

The procs above are used regardless if you compile using the `build_release`
script or the `build_hot_reload` script. However, in the hot reload case, the
contents of this file is compiled as part of `build/hot_reload/game.dll` (or
.dylib/.so on mac/linux). In the hot reload cases some other procedures are
also used in order to facilitate the hot reload functionality:

- game_memory: Run just before a hot reload. That way game_hot_reload.exe has a
	pointer to the game's memory that it can hand to the new game DLL.
- game_hot_reloaded: Run after a hot reload so that the `g` global
	variable can be set to whatever pointer it was in the old DLL.

NOTE: When compiled as part of `build_release`, `build_debug` or `build_web`
then this whole package is just treated as a normal Odin package. No DLL is
created.
*/

package game

import "base:runtime"
import "core:math/linalg"
import "core:log"
import "core:math"
import "core:mem"
import sdl "vendor:sdl3"

default_context := runtime.default_context()

PIXEL_WINDOW_HEIGHT :: 720

Time :: struct {
	past_tick: u64, // The last tick 
	now_tick: u64, // The last tick 
	dt: f32, // Delta time in seconds.
}

Game_Memory :: struct {
	r : RenderData,
	input : Input, // Input state.
	time : Time,

	player_pos: V3f,
	player_rot: V3f,
	run: bool,
}

g: ^Game_Memory

@(export)
game_init_window :: proc() {
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
	}

	if !sdl.Init(sdl.INIT_AUDIO | sdl.INIT_VIDEO | sdl.INIT_GAMEPAD) {
		log.errorf("Failed to initialize SDL! %s", sdl.GetError())
	}
	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(proc "c" (userdata : rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
		context = runtime.default_context()
		log.debugf("SDL Log {}[{}]:{}", category, priority, message)
	}, nil)

	window_flags := sdl.WindowFlags {
		.RESIZABLE,
		.MOUSE_FOCUS,
		.INPUT_FOCUS,
	}
	
	g.r.window = sdl.CreateWindow("Odin SDL Hot Reload Template", 1280, 720, window_flags)
	g.r.gpu = sdl.CreateGPUDevice({.SPIRV}, true, nil)

	ok := sdl.ClaimWindowForGPUDevice(g.r.gpu, g.r.window); assert(ok)

	vert_shd := load_shader(passthrough_vert, .VERTEX, 1)
	frag_shd := load_shader(fullbright_frag, .FRAGMENT, 0)

	vert_attr := []sdl.GPUVertexAttribute {
		{
			location = 0,
			format = .FLOAT3,
			offset = u32(offset_of(Vertex, loc)),
		},
		{
			location = 1,
			format = .FLOAT4,
			offset = u32(offset_of(Vertex, color)),
		},
	}

	g.r.tri_vertex_buffer = sdl.CreateGPUBuffer(g.r.gpu, {
		usage = {.VERTEX},
		size = tri_byte_size(),
	})

	transfer := sdl.CreateGPUTransferBuffer(g.r.gpu,{
		usage = .UPLOAD,
		size = tri_byte_size(),
	})

	transfer_mem := sdl.MapGPUTransferBuffer(g.r.gpu, transfer, false)
	mem.copy(transfer_mem, raw_data(triangle_verts), int(tri_byte_size()))
	sdl.UnmapGPUTransferBuffer(g.r.gpu, transfer)

	copy_cmds := sdl.AcquireGPUCommandBuffer(g.r.gpu)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmds)

	// upload vert data
	sdl.UploadToGPUBuffer(copy_pass, {
		transfer_buffer = transfer,
	}, {
		buffer = g.r.tri_vertex_buffer,
		size = tri_byte_size(),
	}, false)

	sdl.EndGPUCopyPass(copy_pass)
	ok = sdl.SubmitGPUCommandBuffer(copy_cmds); assert(ok)

	g.r.pipeline = sdl.CreateGPUGraphicsPipeline(g.r.gpu, {
		vertex_shader = vert_shd,
		fragment_shader = frag_shd,
		primitive_type = .TRIANGLELIST,
		vertex_input_state = {
			num_vertex_buffers = 1,
			vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription{
				slot = 0,
				pitch = size_of(Vertex),
			}),
			num_vertex_attributes = u32(len(vert_attr)),
			vertex_attributes = raw_data(vert_attr),
		},
		target_info = {
			num_color_targets= 1,
			color_target_descriptions= &(sdl.GPUColorTargetDescription {
				format = sdl.GetGPUSwapchainTextureFormat(g.r.gpu, g.r.window),
			}),
		},
	})

	// If we need to reuse for additional pipelines, we'll want to keep this around.
	// For now, release the shaders since the pipeline is created already.
	sdl.ReleaseGPUShader(g.r.gpu, vert_shd)
	sdl.ReleaseGPUShader(g.r.gpu, frag_shd)
}

@(export)
game_init :: proc() {
	game_hot_reloaded(g)
}

game_camera :: proc() -> Camera {
	w := f32(0)
	h := f32(0)
	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		target = g.player_pos,
		offset = { w/2, h/2, 0},
	}
}

ui_camera :: proc() -> Camera {
	return {
		//zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

update :: proc() {
	g.time.now_tick = sdl.GetTicks()
	g.time.dt = f32(g.time.now_tick - g.time.past_tick) / 1000
	g.time.past_tick = g.time.now_tick

	cache_inputs()

	input: V3f
	if is_key_down(.W) {
		input.y += 0.1
	}
	if is_key_down(.S) {
		input.y -= 0.1
	}
	if is_key_down(.A) {
		input.x -= 0.1
	}
	if is_key_down(.D) {
		input.x += 0.1
	}

	input = linalg.normalize0(input)
	g.player_pos += input * g.time.dt * 10.0
}

draw :: proc() {
	if g.r.gpu == nil || g.r.window == nil{
		return
	}

	cmds := sdl.AcquireGPUCommandBuffer(g.r.gpu)

	swapchain_tex: ^sdl.GPUTexture
	ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmds, g.r.window, &swapchain_tex, nil, nil); assert(ok)
	if swapchain_tex == nil {
		log.errorf("Failed to acquire swapchain texture! %s", sdl.GetError())
		return
	}

	window_dims: [2]i32
	sdl.GetWindowSize(g.r.window, &window_dims[0], &window_dims[1])


	proj_mat := linalg.matrix4_perspective_f32(math.to_radians_f32(70.0), f32(window_dims[0]) / f32(window_dims[1]), 0.001, 2000, false)
	model_mat := linalg.matrix4_translate_f32({g.player_pos.x, g.player_pos.y, 5.0}) * linalg.matrix4_rotate_f32(g.player_rot.z, {0, 0, 1}) * linalg.matrix4_scale_f32({1,1,1})

	ubo := UBO {
		mvp = proj_mat * model_mat, // Combine projection and model matrices.
	}
	
	color_target := sdl.GPUColorTargetInfo{
		texture = swapchain_tex,
		load_op = .CLEAR,
		clear_color = { .4, .4, .4, 1.0 },
	}
	pass := sdl.BeginGPURenderPass(cmds, &color_target, 1, nil)

	sdl.BindGPUGraphicsPipeline(pass, g.r.pipeline)
	sdl.BindGPUVertexBuffers(pass, 0, &(sdl.GPUBufferBinding{ buffer = g.r.tri_vertex_buffer, }), 1)

	sdl.PushGPUVertexUniformData(cmds, 1, &ubo, size_of(ubo))
	sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)

	sdl.EndGPURenderPass(pass)
	ok = sdl.SubmitGPUCommandBuffer(cmds); assert(ok)
}

@(export)
game_update :: proc() {
	update()
	draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}


@(export)
game_should_run :: proc() -> bool {
	return g.run
}

@(export)
game_shutdown :: proc() {
	free(g)
}

@(export)
game_shutdown_window :: proc() {
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return is_key_pressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return is_key_pressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	sdl.SetWindowSize(g.r.window, i32(w), i32(h))
}
