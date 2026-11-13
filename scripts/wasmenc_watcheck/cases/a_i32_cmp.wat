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

    ;; group: Eq(0)
    block
      i32.const 0
      i32.const 0
      i32.eq
      drop
    end
    ;; group: Ne(0)
    block
      i32.const 0
      i32.const 0
      i32.ne
      drop
    end
    ;; group: Lt(0)
    block
      i32.const 0
      i32.const 0
      i32.lt_s
      drop
    end
    ;; group: Le(0)
    block
      i32.const 0
      i32.const 0
      i32.le_s
      drop
    end
    ;; group: Gt(0)
    block
      i32.const 0
      i32.const 0
      i32.gt_s
      drop
    end
    ;; group: Ge(0)
    block
      i32.const 0
      i32.const 0
      i32.ge_s
      drop
    end
  )
)
