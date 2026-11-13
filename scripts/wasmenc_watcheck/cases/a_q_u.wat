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

    ;; group: UDivQ(0)
    block
      i64.const 0
      i64.const 0
      i64.div_u
      drop
    end
    ;; group: UModQ(0)
    block
      i64.const 0
      i64.const 0
      i64.rem_u
      drop
    end
    ;; group: ULtQ(0)
    block
      i64.const 0
      i64.const 0
      i64.lt_u
      drop
    end
    ;; group: ULeQ(0)
    block
      i64.const 0
      i64.const 0
      i64.le_u
      drop
    end
    ;; group: UGtQ(0)
    block
      i64.const 0
      i64.const 0
      i64.gt_u
      drop
    end
    ;; group: UGeQ(0)
    block
      i64.const 0
      i64.const 0
      i64.ge_u
      drop
    end
  )
)
