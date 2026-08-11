/// Subscribe to browser viewport and lifecycle changes.
@external(javascript, "./viewport_ffi.mjs", "subscribe")
pub fn subscribe(on_resize: fn(Int, Int) -> Nil, on_hidden: fn() -> Nil) -> Nil
