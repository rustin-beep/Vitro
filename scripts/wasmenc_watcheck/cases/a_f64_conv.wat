;; wasmenc watcheck case (generated skeleton, human-reviewed)
(module
  (import "env" "vitro_host_call" (func $host (param i32 i32) (result i64)))
  (memory 1 1)
  (global $g0 (mut i32) (i32.const 0))
  (global $g1 (mut i32) (i32.const 0))
  (global $g2 (mut i32) (i32.const 0))
  (global $g3 (mut i32) (i32.const 0))
  (global $g4 (mut i32) (i32.const 0))
  (global $g5 (mut i64) (i64.const 0))
  (func (export "main") (local i32 i32 i32 i64 f64 f32)

    ;; group: CastI2D(0)
    block
      i32.const 0
      f64.convert_i32_s
      drop
    end
    ;; group: CastF2D(0)
    block
      f32.const 0
      f64.promote_f32
      drop
    end
    ;; group: CastD2I(0)
    block
      f64.const 0
      i32.trunc_sat_f64_s
      drop
    end
    ;; group: CastD2F(0)
    block
      f64.const 0
      f32.demote_f64
      drop
    end
    ;; group: CastU2D(0)
    block
      i32.const 0
      f64.convert_i32_u
      drop
    end
    ;; group: CastUQ2D(0)
    block
      i64.const 0
      f64.convert_i64_u
      drop
    end
  )
)
