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

    ;; group: EqD(0)
    block
      f64.const 0
      f64.const 0
      f64.eq
      drop
    end
    ;; group: NeD(0)
    block
      f64.const 0
      f64.const 0
      f64.ne
      drop
    end
    ;; group: LtD(0)
    block
      f64.const 0
      f64.const 0
      f64.lt
      drop
    end
    ;; group: LeD(0)
    block
      f64.const 0
      f64.const 0
      f64.le
      drop
    end
    ;; group: GtD(0)
    block
      f64.const 0
      f64.const 0
      f64.gt
      drop
    end
    ;; group: GeD(0)
    block
      f64.const 0
      f64.const 0
      f64.ge
      drop
    end
  )
)
