// @category: failfast_chain
// 分层 fail-fast 短路现状锚（#20 方案 B 评估批，2026-10-07）：词法错
//（字符串未闭合）短路 parse/typeck——现状只报 E1003/E1002 两条，后续
// bool/undefined_type 的诊断被遮蔽（Clang 同文件跨层报 4 条）。
// **#20 方案 C（诊断分流降级）已随批四第二条 SEVERITY-FORMAT 销案兑现**
//（W3032/W3035/W3062/W3063 降级放行——typeck→codegen 层遮蔽大幅缓解，
// sev_probe 形态实证）；**方案 B（词法/parse 跨层继续）评估暂缓**——
// 未闭合字符串吞没后续 token，跨层继续的假错误雪崩风险（plotter 171
// 条级联先例）+「先修词法错」的教学合理性。本用例锁短路现状，B 批
// 若立项则翻转为跨层全集预期（issue #20 红锚约定）。
int main() {
    int a = "unterminated
    bool flag = true;
    undefined_type x;
    return 0;
}
