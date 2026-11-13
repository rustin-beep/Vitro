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

    ;; group: EqF(0)
    block
      f32.const 0
      f32.const 0
      f32.eq
      drop
    end
    ;; group: NeF(0)
    block
      f32.const 0
      f32.const 0
      f32.ne
      drop
    end
    ;; group: LtF(0)
    block
      f32.const 0
      f32.const 0
      f32.lt
      drop
    end
    ;; group: LeF(0)
    block
      f32.const 0
      f32.const 0
      f32.le
      drop
    end
    ;; group: GtF(0)
    block
      f32.const 0
      f32.const 0
      f32.gt
      drop
    end
    ;; group: GeF(0)
    block
      f32.const 0
      f32.const 0
      f32.ge
      drop
    end
  )
)
