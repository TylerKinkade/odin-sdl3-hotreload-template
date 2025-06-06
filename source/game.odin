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
import sdl "vendor:sdl3"

default_context := runtime.default_context()

PIXEL_WINDOW_HEIGHT :: 180

RenderData :: struct {
	window: ^sdl.Window, // Pointer to the SDL window.
	renderer : ^sdl.Renderer, // Pointer to the SDL renderer.
	gpu : ^sdl.GPUDevice, // Pointer to the SDL renderer.
	pipeline : ^sdl.GPUGraphicsPipeline, // Pointer to the GPU pipeline.
} 

PressState :: struct {
	pressed: bool, // If the key was pressed this frame.
	repeat: bool, // If the key is being held down.
}

Input :: struct {
	mouse_delta: V2f, // The mouse delta since last frame.
	mouse_loc: V2f, // The mouse position in pixels.

	keys_down: #sparse[sdl.Scancode]PressState,
	mb_down: [sdl.MouseButtonFlag]PressState,
}

Time :: struct {
	past_ns: u64, // The last tick in nanoseconds.
	now_ns: u64, // The last tick in nanoseconds.
	dt: f32, // Delta time in seconds.
}

Game_Memory :: struct {
	r : RenderData,
	input : Input, // Input state.
	time : Time,

	player_pos: V2f,
	run: bool,
}

g: ^Game_Memory

test_vert := #load("../assets/shaders/test.spv.vert")
test_frag := #load("../assets/shaders/test.spv.frag")

load_shader :: proc(code : []u8, stage : sdl.GPUShaderStage) -> ^sdl.GPUShader {
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
	})

	if shader == nil {
		log.errorf("Failed to create GPU shader! %s", sdl.GetError())
		return nil
	}

	return shader
}

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

	vert_shd := load_shader(test_vert, .VERTEX)
	frag_shd := load_shader(test_frag, .FRAGMENT)

	g.r.pipeline = sdl.CreateGPUGraphicsPipeline(g.r.gpu, {
		vertex_shader = vert_shd,
		fragment_shader = frag_shd,
		primitive_type = .TRIANGLELIST,
		target_info = {
			num_color_targets= 1,
			color_target_descriptions= &(sdl.GPUColorTargetDescription {
				format = sdl.GetGPUSwapchainTextureFormat(g.r.gpu, g.r.window),
			}),
		},
	})

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
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> Camera {
	return {
		//zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

update :: proc() {
	g.time.past_ns = g.time.now_ns
	g.time.now_ns = sdl.GetTicksNS()
	g.time.dt = f32(g.time.now_ns - g.time.past_ns) / f32(1_000_000_000)
	
	g.input.mouse_delta = {0, 0}

	ev: sdl.Event
	for sdl.PollEvent(&ev) {
		#partial switch ev.type {
		case .KEY_DOWN:
			g.input.keys_down[ev.key.scancode] = PressState {
				pressed = true,
				repeat = ev.key.repeat,
			}
		case .KEY_UP:
			g.input.keys_down[ev.key.scancode] = PressState {
				pressed = false,
				repeat = false, 
			}
		case .MOUSE_MOTION:
			g.input.mouse_delta = {f32(ev.motion.xrel), f32(ev.motion.yrel)}
			g.input.mouse_loc = {f32(ev.motion.x), f32(ev.motion.y)}
			fallthrough
		case .MOUSE_BUTTON_UP:
			fallthrough
		case .MOUSE_BUTTON_DOWN:
			for flag in sdl.MouseButtonFlag {
				active_flags := sdl.GetMouseState(nil, nil)
				g.input.mb_down[flag] = PressState {
					pressed = flag in active_flags,
					repeat = ev.button.down, // Mouse button down events are not repeated.
				}
			}
		case .QUIT:
			g.run = false 
		}
		log.debugf("Event: %s", ev.type)
	}

	input: V2f
	if is_key_down(.W) {
		input.y -= 1
	}
	if is_key_down(.S) {
		input.y += 1
	}
	if is_key_down(.A) {
		input.x -= 1
	}
	if is_key_down(.D) {
		input.x = 1
	}

	input = linalg.normalize0(input)
	g.player_pos += input * g.time.dt * 200
}

draw :: proc() {
	if g.r.gpu == nil || g.r.window == nil{
		return
	}

	cmds := sdl.AcquireGPUCommandBuffer(g.r.gpu)
	swapchain_tex: ^sdl.GPUTexture
	ok := sdl.WaitAndAcquireGPUSwapchainTexture(cmds, g.r.window, &swapchain_tex, nil, nil); assert(ok)
	color_target := sdl.GPUColorTargetInfo{
		texture = swapchain_tex,
		load_op = .CLEAR,
		clear_color = { g.input.mb_down[.LEFT].pressed?.5:.3 , .6, .2, 1.0 },
	}
	pass := sdl.BeginGPURenderPass(cmds, &color_target, 1, nil)
	
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
