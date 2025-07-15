package game
import sdl "vendor:sdl3"
import "core:log"

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

is_key_pressed :: proc(scancode: sdl.Scancode) -> bool {
    key := g.input.keys_down[scancode]
    return key.pressed && !key.repeat
}

is_key_down :: proc(scancode: sdl.Scancode) -> bool {
    key := g.input.keys_down[scancode]
    return key.pressed
}

cache_inputs :: proc() {
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
}