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

    ;; group: CastI2Q(0)
    block
      i32.const 0
      i64.extend_i32_s
      drop
    end
    ;; group: CastQ2I(0)
    block
      i64.const 0
      i32.wrap_i64
      drop
    end
    ;; group: CastQ2D(0)
    block
      i64.const 0
      f64.convert_i64_s
      drop
    end
    ;; group: CastD2Q(0)
    block
      f64.const 0
      i64.trunc_sat_f64_s
      drop
    end
    ;; group: CastD2UQ(0) —— #471 f64→u64 饱和无符号
    block
      f64.const 0
      i64.trunc_sat_f64_u
      drop
    end
    ;; group: CastU2Q(0)
    block
      i32.const 0
      i64.extend_i32_u
      drop
    end
  )
)
