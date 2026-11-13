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

    ;; group: EqQ(0)
    block
      i64.const 0
      i64.const 0
      i64.eq
      drop
    end
    ;; group: NeQ(0)
    block
      i64.const 0
      i64.const 0
      i64.ne
      drop
    end
    ;; group: LtQ(0)
    block
      i64.const 0
      i64.const 0
      i64.lt_s
      drop
    end
    ;; group: LeQ(0)
    block
      i64.const 0
      i64.const 0
      i64.le_s
      drop
    end
    ;; group: GtQ(0)
    block
      i64.const 0
      i64.const 0
      i64.gt_s
      drop
    end
    ;; group: GeQ(0)
    block
      i64.const 0
      i64.const 0
      i64.ge_s
      drop
    end
  )
)
