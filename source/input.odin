package game
import sdl "vendor:sdl3"

is_key_pressed :: proc(scancode: sdl.Scancode) -> bool {
    key := g.input.keys_down[scancode]
    return key.pressed && !key.repeat
}

is_key_down :: proc(scancode: sdl.Scancode) -> bool {
    key := g.input.keys_down[scancode]
    return key.pressed
}