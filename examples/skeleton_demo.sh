#!/usr/bin/env bash
# 分期骨架查询（GET /phasing-skeleton）端到端调用示例
# 前提：服务已启动（docker compose up --build），监听 http://localhost:8000
#
# 覆盖：
#   0. 无断言时的空骨架（已登记地层各自成组、空边）
#   1. 同一期等价组、孤立地层
#   2. 平行断言只形成一条边、传递边被省略（omitted_edge_count）
#   3. 修订号过期返回当前修订号（STALE_REVISION，不输出混合版本）
set -euo pipefail

BASE="${BASE_URL:-http://localhost:8000}"
pp() { python3 -m json.tool 2>/dev/null || cat; }

echo "== 0. 健康检查 =="
curl -s "$BASE/health" | pp

echo; echo "== 1. 登记 7 个地层（L1..L7，L7 全程无断言，为孤立地层） =="
for s in L1 L2 L3 L4 L5 L6 L7; do
  curl -s -X POST "$BASE/strata" -H 'Content-Type: application/json' \
    -d "{\"stratum_id\": \"$s\", \"site\": \"乙遗址\"}" >/dev/null
done
echo "已登记：L1 L2 L3 L4 L5 L6 L7"

echo; echo "== 2. 修订号 0 下的空骨架（无断言：全部各自成组、空边） =="
curl -s "$BASE/phasing-skeleton?expected_revision=0" | pp

echo; echo "== 3. 批次 1（0 -> 1）：L1~L2；L2 早于 L3；L3 早于 L4；L4 早于 L5；"
echo "           L2 早于 L5（与 L2->L3->L4->L5 平行的冗余直连）；L4 早于 L6 =="
curl -s -X POST "$BASE/batches" -H 'Content-Type: application/json' -d '{
  "expected_revision": 0,
  "operations": [
    {"op": "assert", "evidence_id": "EV-001", "stratum_a": "L1", "stratum_b": "L2", "relation": "same_period"},
    {"op": "assert", "evidence_id": "EV-002", "stratum_a": "L2", "stratum_b": "L3", "relation": "earlier_than"},
    {"op": "assert", "evidence_id": "EV-003", "stratum_a": "L3", "stratum_b": "L4", "relation": "earlier_than"},
    {"op": "assert", "evidence_id": "EV-004", "stratum_a": "L4", "stratum_b": "L5", "relation": "earlier_than"},
    {"op": "assert", "evidence_id": "EV-009", "stratum_a": "L2", "stratum_b": "L5", "relation": "earlier_than"},
    {"op": "assert", "evidence_id": "EV-005", "stratum_a": "L4", "stratum_b": "L6", "relation": "earlier_than"}
  ]}' | pp

echo; echo "== 4. 查询修订号 1 的分期骨架 =="
echo "   预期分组：1=[L1,L2] 2=[L3] 3=[L4] 4=[L5] 5=[L6] 6=[L7]"
echo "   保留边：1->2(EV-002)、2->3(EV-003)、3->4(EV-004)、3->5(EV-005)"
echo "   L2 早于 L5(EV-009) 可经组 1->2->3->4 到达，被传递关系省略：omitted_edge_count=1"
curl -s "$BASE/phasing-skeleton?expected_revision=1" | pp

echo; echo "== 5. 修订号过期（携带 0，当前为 1）：HTTP 409 STALE_REVISION，只回当前修订号 =="
curl -s -w "\nHTTP %{http_code}\n" "$BASE/phasing-skeleton?expected_revision=0" | pp

echo; echo "== 6. 平行断言示例：批次 2（1 -> 2）再断言一条 L3 早于 L4（EV-010） =="
curl -s -X POST "$BASE/batches" -H 'Content-Type: application/json' -d '{
  "expected_revision": 1,
  "operations": [
    {"op": "assert", "evidence_id": "EV-010", "stratum_a": "L3", "stratum_b": "L4", "relation": "earlier_than"}
  ]}' | pp

echo; echo "== 7. 查询修订号 2：组 2->组 3（L3->L4）同一条边列出全部生效证据（EV-003、EV-010，按编号排序） =="
curl -s "$BASE/phasing-skeleton?expected_revision=2" | pp

echo; echo "全部示例执行完毕。"
