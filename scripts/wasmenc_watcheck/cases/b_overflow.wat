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

    ;; group: Add(0)
    block
      i32.const 0
      i32.const 0
      local.set 1
      i64.extend_i32_s
      local.get 1
      i64.extend_i32_s
      i64.add
      local.set 3
      block
      local.get 3
      i32.wrap_i64
      i64.extend_i32_s
      local.get 3
      i64.eq
      br_if 0
      unreachable
      end
      local.get 3
      i32.wrap_i64
      drop
    end
    ;; group: Sub(0)
    block
      i32.const 0
      i32.const 0
      local.set 1
      i64.extend_i32_s
      local.get 1
      i64.extend_i32_s
      i64.sub
      local.set 3
      block
      local.get 3
      i32.wrap_i64
      i64.extend_i32_s
      local.get 3
      i64.eq
      br_if 0
      unreachable
      end
      local.get 3
      i32.wrap_i64
      drop
    end
    ;; group: Mul(0)
    block
      i32.const 0
      i32.const 0
      local.set 1
      i64.extend_i32_s
      local.get 1
      i64.extend_i32_s
      i64.mul
      local.set 3
      block
      local.get 3
      i32.wrap_i64
      i64.extend_i32_s
      local.get 3
      i64.eq
      br_if 0
      unreachable
      end
      local.get 3
      i32.wrap_i64
      drop
    end
    ;; group: Neg(0)
    block
      i32.const 0
      local.set 0
      block
      local.get 0
      i32.const -2147483648
      i32.ne
      br_if 0
      unreachable
      end
      i32.const 0
      local.get 0
      i32.sub
      drop
    end
    ;; group: NegQ(0)
    block
      i64.const 0
      local.set 3
      block
      local.get 3
      i64.const -9223372036854775808
      i64.ne
      br_if 0
      unreachable
      end
      i64.const 0
      local.get 3
      i64.sub
      drop
    end
    ;; group: UNeg(0)
    block
      i32.const 0
      local.set 0
      i32.const 0
      local.get 0
      i32.sub
      drop
    end
    ;; group: UNegQ(0)
    block
      i64.const 0
      local.set 3
      i64.const 0
      local.get 3
      i64.sub
      drop
    end
  )
)
