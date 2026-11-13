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

    ;; group: PushConstF(1069547520)
    block
      f32.const 1.5
      drop
    end
    ;; group: AddF(0)
    block
      f32.const 0
      f32.const 0
      f32.add
      drop
    end
    ;; group: SubF(0)
    block
      f32.const 0
      f32.const 0
      f32.sub
      drop
    end
    ;; group: MulF(0)
    block
      f32.const 0
      f32.const 0
      f32.mul
      drop
    end
    ;; group: DivF(0)
    block
      f32.const 0
      f32.const 0
      f32.div
      drop
    end
    ;; group: NegF(0)
    block
      f32.const 0
      f32.neg
      drop
    end
  )
)
