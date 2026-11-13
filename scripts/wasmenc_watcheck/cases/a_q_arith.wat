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

    ;; group: AddQ(0)
    block
      i64.const 0
      i64.const 0
      i64.add
      drop
    end
    ;; group: SubQ(0)
    block
      i64.const 0
      i64.const 0
      i64.sub
      drop
    end
    ;; group: MulQ(0)
    block
      i64.const 0
      i64.const 0
      i64.mul
      drop
    end
    ;; group: DivQ(0)
    block
      i64.const 0
      i64.const 0
      i64.div_s
      drop
    end
    ;; group: ModQ(0)
    block
      i64.const 0
      i64.const 0
      i64.rem_s
      drop
    end
  )
)
