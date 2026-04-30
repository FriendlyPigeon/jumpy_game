import gleam/float
import gleam/int
import gleam/list
import gleam/time/duration
import input
import lustre
import lustre/attribute
import lustre/effect
import lustre/element/html
import lustre/event
import tiramisu
import tiramisu/camera
import tiramisu/primitive
import tiramisu/renderer
import tiramisu/scene
import tiramisu/transform
import vec/vec2
import vec/vec3

const max_charge = 5.0

type Platform {
  Platform(id: Int, position: vec3.Vec3(Float))
}

pub fn main() -> Nil {
  let assert Ok(_) = tiramisu.register(tiramisu.builtin_extensions())
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

type Model {
  Model(
    time: Float,
    player_position: vec3.Vec3(Float),
    input: input.InputState,
    charged_velocity: Float,
    in_air: Bool,
    flying_velocity: vec2.Vec2(Float),
    platform_positions: List(Platform),
    last_scored_platform_id: Int,
    next_platform_id: Int,
    score: Int,
    extra_lives: Int,
  )
}

type Msg {
  Tick(renderer.Tick)
  KeyDown(input.Key)
  KeyUp(input.Key)
  MouseDown(input.MouseButton)
  MouseUp(input.MouseButton)
  PlayerLandedPlatform
}

fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  #(initial_model(), effect.none())
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    Tick(ctx) -> {
      let model =
        update_physics(model, ctx)
        |> check_reset()
        |> shift_screen_if_needed()
      // |> delete_and_add_platforms_if_needed()

      #(Model(..model, input: input.end_frame(model.input)), effect.none())
    }
    KeyDown(key) -> #(
      Model(..model, input: input.key_down(model.input, key)),
      effect.none(),
    )
    KeyUp(key) -> #(
      Model(..model, input: input.key_up(model.input, key)),
      effect.none(),
    )
    MouseDown(button) -> {
      // echo model

      #(
        Model(..model, input: input.mouse_down(model.input, button)),
        effect.none(),
      )
    }
    MouseUp(button) -> #(
      Model(..model, input: input.mouse_up(model.input, button)),
      effect.none(),
    )
    PlayerLandedPlatform -> {
      #(Model(..model, in_air: False), effect.none())
    }
  }
}

fn shift_screen_if_needed(model: Model) -> Model {
  let shift_amount = model.player_position.x +. 250.0

  case shift_amount >. 0.0 {
    True ->
      Model(
        ..model,
        player_position: vec3.Vec3(
          -250.0,
          model.player_position.y,
          model.player_position.z,
        ),
        platform_positions: list.map(
          model.platform_positions,
          fn(platform_position) {
            Platform(
              platform_position.id,
              vec3.Vec3(
                platform_position.position.x -. shift_amount,
                platform_position.position.y,
                platform_position.position.z,
              ),
            )
          },
        ),
      )
    False -> model
  }
}

fn check_reset(model: Model) -> Model {
  case box_touching_border(model.player_position), model.extra_lives > 0 {
    True, False -> initial_model()
    True, True ->
      Model(
        ..initial_model(),
        extra_lives: model.extra_lives - 1,
        score: model.score,
      )
    False, _ -> model
  }
}

fn initial_model() -> Model {
  Model(
    time: 0.0,
    player_position: vec3.Vec3(-250.0, 0.0, 0.0),
    input: input.new(),
    charged_velocity: 0.0,
    score: 0,
    extra_lives: 0,
    in_air: True,
    flying_velocity: vec2.Vec2(0.0, 0.0),
    platform_positions: [
      Platform(0, vec3.Vec3(-250.0, -20.0, 0.0)),
    ],
    last_scored_platform_id: 0,
    next_platform_id: 2,
  )
}

fn update_physics(model: Model, ctx: renderer.Tick) -> Model {
  let delta_seconds = duration.to_seconds(ctx.delta_time)

  case model.in_air {
    // in air...
    True ->
      case model.charged_velocity >. 0.0 {
        // ... and just released charge and started flying
        True ->
          Model(
            ..model,
            flying_velocity: vec2.Vec2(
              model.charged_velocity,
              model.charged_velocity *. 2.0,
            ),
            charged_velocity: 0.0,
          )
        // ... and already flying ...
        False ->
          case player_touching_platform(model) {
            // ... and just landed on platform
            True -> {
              let closest_platform_id = get_closest_platform(model).id
              let new_score = case
                model.last_scored_platform_id == closest_platform_id
              {
                True -> model.score
                False -> model.score + 1
              }
              let new_extra_lives = case
                int.modulo(new_score, 10),
                new_score != model.score
              {
                Ok(0), True -> model.extra_lives + 1
                Ok(_), _ -> model.extra_lives
                Error(_), _ -> model.extra_lives
              }

              let landed_platform = get_closest_platform(model)

              maybe_spawn_rightmost_platform(
                Model(
                  ..model,
                  in_air: False,
                  flying_velocity: vec2.Vec2(0.0, 0.0),
                  score: new_score,
                  last_scored_platform_id: closest_platform_id,
                  extra_lives: new_extra_lives,
                ),
                landed_platform,
              )
            }
            // ... and still flying
            False ->
              Model(
                ..model,
                flying_velocity: vec2.Vec2(
                  model.flying_velocity.x,
                  model.flying_velocity.y -. { 20.0 *. delta_seconds },
                ),
                player_position: vec3.Vec3(
                  model.player_position.x +. model.flying_velocity.x,
                  model.player_position.y +. model.flying_velocity.y,
                  model.player_position.z,
                ),
              )
          }
      }
    // on ground...
    False ->
      case jump_charge_held(model.input) {
        // ... and charging jump still
        True ->
          Model(
            ..model,
            charged_velocity: float.min(
              model.charged_velocity +. { 3.0 *. delta_seconds },
              max_charge,
            ),
          )
        // ... and not charging jump ...
        False ->
          case model.charged_velocity >. 0.0 {
            // ... but just released charge and started flying
            True -> Model(..model, in_air: True)
            // ... and haven't started charging jump
            False -> model
          }
      }
  }
}

fn jump_charge_held(input_state: input.InputState) -> Bool {
  input.is_pressed(input_state, input.Space)
  || input.is_mouse_pressed(input_state, input.LeftButton)
}

fn maybe_spawn_rightmost_platform(
  model: Model,
  landed_platform: Platform,
) -> Model {
  case landed_platform.id == rightmost_platform_id(model.platform_positions) {
    True -> {
      let x_variance = { float.random() -. 0.5 } *. 120.0

      Model(
        ..model,
        platform_positions: list.append(model.platform_positions, [
          Platform(
            model.next_platform_id,
            vec3.Vec3(
              landed_platform.position.x +. 280.0 +. x_variance,
              { float.random() -. 0.5 } *. 200.0,
              0.0,
            ),
          ),
        ]),
        next_platform_id: model.next_platform_id + 1,
      )
    }
    False -> model
  }
}

fn rightmost_platform_id(platforms: List(Platform)) -> Int {
  case platforms {
    [] -> 0
    [rightmost_platform, ..remaining_platforms] ->
      list.fold(
        remaining_platforms,
        rightmost_platform,
        fn(current_rightmost, platform) {
          case platform.position.x >. current_rightmost.position.x {
            True -> platform
            False -> current_rightmost
          }
        },
      ).id
  }
}

fn get_closest_platform(model: Model) -> Platform {
  case model.platform_positions {
    [] -> Platform(0, vec3.Vec3(0.0, 0.0, 0.0))
    [closest_platform, ..remaining_platforms] ->
      list.fold(
        remaining_platforms,
        closest_platform,
        fn(current_closest, platform_position) {
          case
            platform_distance_sq(
              model.player_position,
              platform_position.position,
            )
            <. platform_distance_sq(
              model.player_position,
              current_closest.position,
            )
          {
            True -> platform_position
            False -> current_closest
          }
        },
      )
  }
}

fn platform_distance_sq(
  player_position: vec3.Vec3(Float),
  platform_position: vec3.Vec3(Float),
) -> Float {
  let x_distance = player_position.x -. platform_position.x
  let y_distance = player_position.y -. platform_position.y

  x_distance *. x_distance +. y_distance *. y_distance
}

fn player_touching_platform(model: Model) -> Bool {
  list.any(model.platform_positions, fn(platform_position) {
    // make sure flying velocity is not positive (i.e. player is falling onto platform, not jumping up off it)
    case model.flying_velocity.y <=. 0.0 {
      True -> {
        let platform_top = platform_position.position.y +. 15.0
        let platform_left = platform_position.position.x -. 25.0
        let platform_right = platform_position.position.x +. 25.0

        model.player_position.y >=. platform_top -. 10.0
        && model.player_position.y <=. platform_top
        && model.player_position.x >=. platform_left -. 10.0
        && model.player_position.x <=. platform_right +. 10.0
      }
      False -> False
    }
  })
}

fn box_touching_border(position: vec3.Vec3(Float)) -> Bool {
  position.x <=. -390.0 || position.x >=. 390.0 || position.y <=. -240.0
}

fn view(model: Model) {
  html.div([attribute.style("max-width", "800px")], [
    html.h1([attribute.style("text-align", "center")], [
      html.text(
        "Score: "
        <> int.to_string(model.score)
        <> " Lives: "
        <> int.to_string(model.extra_lives),
      ),
    ]),
    html.div([attribute.class("progress-bar-container")], [
      html.div(
        [
          attribute.class("progress-bar"),
          attribute.style(
            "width",
            float.to_string(model.charged_velocity /. max_charge *. 100.0)
              <> "%",
          ),
        ],
        [],
      ),
    ]),
    tiramisu.renderer(
      "renderer",
      [
        renderer.on_tick(Tick),
        renderer.width(800),
        renderer.height(500),
        event.prevent_default(input.on_keydown(KeyDown)),
        input.on_keyup(KeyUp),
        input.on_mousedown(MouseDown),
        input.on_mouseup(MouseUp),
        attribute.attribute("tabindex", "0"),
        attribute.style("touch-action", "none"),
      ],
      [
        tiramisu.scene("scene", [scene.background_color(0xffffff)], [
          tiramisu.camera(
            "camera",
            [
              camera.active(True),
              camera.orthographic(),
              camera.left(-400.0),
              camera.right(400.0),
              camera.top(250.0),
              camera.bottom(-250.0),
              camera.near(0.1),
              camera.far(20.0),
              transform.position(vec3.Vec3(0.0, 0.0, 20.0)),
            ],
            [],
          ),
          tiramisu.primitive(
            "box",
            [
              primitive.box(vec3.Vec3(20.0, 20.0, 1.0)),
              transform.position(model.player_position),
            ],
            [],
          ),
          ..list.map(model.platform_positions, fn(platform_position) {
            tiramisu.primitive(
              "platform_" <> int.to_string(platform_position.id),
              [
                primitive.box(vec3.Vec3(50.0, 10.0, 1.0)),
                transform.position(platform_position.position),
              ],
              [],
            )
          })
        ]),
      ],
    ),
  ])
}
