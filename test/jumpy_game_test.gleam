import gleeunit
import input

pub fn main() -> Nil {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn clear_input_test() {
  let state = input.new()
  let state = input.key_down(state, input.Space)
  let state = input.mouse_down(state, input.LeftButton)
  let cleared = input.clear(state)

  assert !input.is_pressed(cleared, input.Space)
  assert !input.is_mouse_pressed(cleared, input.LeftButton)
}
