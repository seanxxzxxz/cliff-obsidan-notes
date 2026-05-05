
可以用 OpenClaw 的 agent 来做，**但不要让 agent 单独“自由发挥”完成对账**。  
你这个任务最稳的做法是：

**规则脚本负责“匹配、去重、保留哪一条”**  
**agent 负责“字段映射、疑难判断、分类、复核说明、结果分析”**

原因很简单：你现在处理的是多来源 CSV 合并，这本质上是一个**数据清洗与对账**任务，最怕“看起来聪明、实际不稳定”。OpenClaw 很适合给你做独立 agent、独立 workspace，并按 agent 限制工具；多 agent 和工具隔离是它的官方能力。([OpenClaw](https://docs.openclaw.ai/zh-CN/cli/agents?utm_source=chatgpt.com "agents - OpenClaw"))

## 我对你这个场景的明确建议

**要做，但先做一个“零钱池对账 agent”，不要直接上“财产总管”。**

这个 agent 的任务只有 4 个：

1. 读取多份原始 CSV 的字段说明
    
2. 帮你把不同来源映射到统一字段
    
3. 对“匹配不确定”的记录给出候选和理由
    
4. 对清洗后的总表做分类和月度分析
    

真正的“删重复、识别内部转账、优先保留微信/支付宝商户信息”这类逻辑，建议先用**固定规则**完成，再把结果交给 agent。这样最稳。

---

## 你这次的处理目标，先定义清楚

你不是要得到“所有账户流水”。  
你要得到的是：

**2026-01-01 到今天的“零钱池真实交易流水”**

也就是：

- 保留真实收入
    
- 保留真实支出
    
- 去掉零钱池内部转移
    
- 去掉微信/支付宝 与 银行扣款的重复镜像
    
- 尽量保留**微信/支付宝那条更接近真实商户信息**的记录
    
- 输出 1 份统一 CSV
    

这个目标非常适合做成一条固定流水线。

---

## 我建议你现在就按这个架构开始

### 一层：原始输入层

放原始 CSV，不改内容。

建议目录：

```text
~/AI-Lab/finance-data/reconcile/
  raw/
    wechat/
    alipay/
    bank-cmb/
    bank-citic/
    bank-xxx/
  mapped/
  normalized/
  review/
  output/
  rules/
```

### 二层：统一字段层

把所有 CSV 先映射成统一字段。

统一字段建议先用这一版：

```csv
source,source_file,source_row_id,txn_date,txn_time,amount,direction,account_name,counterparty,merchant,channel,txn_type,remark,balance,currency
```

说明：

- `source`: wechat / alipay / bank_cmb ...
    
- `source_row_id`: 原文件的唯一行号，方便追溯
    
- `direction`: income / expense / transfer / unknown
    
- `channel`: wechat / alipay / bank / card
    
- `merchant`: 优先保留商户信息
    
- `remark`: 原始备注
    
- `txn_type`: 消费 / 转账 / 提现 / 退款 / 红包 / 利息等
    

### 三层：对账规则层

这里才做匹配、合并、去重。

### 四层：分析层

把最终干净 CSV 交给 agent 去分类和分析。

---

## 先不要让 agent 直接决定的事

下面这些，优先用规则，不要先交给模型拍脑袋：

### 1. 哪两笔是同一笔交易

先用规则匹配：

- 金额相同
    
- 日期相同或相近
    
- 时间差在一个阈值内，比如 0–10 分钟
    
- 一条来自微信/支付宝，一条来自银行卡
    
- 方向相反或语义对应
    
- 备注里含“财付通”“微信支付”“支付宝”“快捷支付”等
    

### 2. 哪些是零钱池内部转移

例如：

- A 银行卡 → B 银行卡
    
- 微信零钱 ↔ 银行卡
    
- 支付宝余额 ↔ 银行卡
    
- 自己账户间转入转出
    

这些要识别成 `internal_transfer = true`，从最终“真实收支流水”里排除。

### 3. 保留哪条作为主记录

你的原则可以设成：

- **微信/支付宝记录优先于银行卡扣款记录**
    
- 因为微信/支付宝通常商户信息更完整
    
- 银行卡那条保留为 `matched_funding_record` 供追溯，不作为最终主流水
    

这条原则很适合你现在的业务目标。

---

## 第一版匹配规则，我建议你就这样定

### 规则 A：支付渠道 + 银行卡镜像匹配

满足这些条件时，认为是一笔真实消费：

- 金额绝对值相同
    
- 日期相同
    
- 时间差不超过 10 分钟
    
- 一条来自微信/支付宝
    
- 另一条来自银行卡
    
- 银行卡备注包含以下之一：
    
    - 微信
        
    - 财付通
        
    - 支付宝
        
    - 快捷支付
        
    - 网联
        
    - 银联代扣
        

处理方式：

- 保留微信/支付宝记录
    
- 银行卡记录打上 `matched_duplicate_bank_leg`
    
- 最终主流水里删除银行卡镜像
    

### 规则 B：银行卡之间内部转账

满足：

- 两条都来自你的银行卡
    
- 金额相同
    
- 日期相同或次日
    
- 一入一出
    
- 备注含“转账”“他行转入”“本行转账”“手机银行”“网银”等
    

处理方式：

- 标记 `internal_transfer`
    
- 从最终真实收支流水排除
    

### 规则 C：微信零钱 / 支付宝余额充值提现

满足：

- 备注有“充值”“提现”“转入余额”“余额宝转出”等
    
- 另一来源存在同金额反向记录
    

处理方式：

- 标记 `internal_transfer`
    
- 排除
    

### 规则 D：无法高置信度匹配

不要自动删。  
输出到：

```text
review/unmatched_candidates.csv
```

让你或 agent 复核。

---

## 所以，OpenClaw 在这里怎么用

### 我建议你先建一个新 agent

名字就叫：

**`wallet-reconcile`**

OpenClaw 官方支持用 `openclaw agents add <id> --workspace <dir> --model <id>` 新建隔离 agent。([OpenClaw](https://docs.openclaw.ai/zh-CN/cli/agents?utm_source=chatgpt.com "agents - OpenClaw"))

你执行：

```bash
openclaw agents add wallet-reconcile --workspace ~/.openclaw/workspace-wallet-reconcile --model ollama/qwen3:8b --non-interactive
```

### 这个 agent 先只做这些事

- 读取 `rules/`
    
- 读取原始 CSV 样本和映射后的 CSV
    
- 输出字段映射建议
    
- 输出匹配规则说明
    
- 审核 `unmatched_candidates.csv`
    
- 对最终结果做分类和分析
    

### 这个 agent 暂时不要做这些事

- 不要联网
    
- 不要浏览网页
    
- 不要碰你别的财务目录
    
- 不要自己跑高权限 exec
    

因为这一步的核心是“稳定清洗”，不是“自主行动”。

---

## 你现在最适合的启动方式

### 第一步：先做字段映射，不做合并

先拿每个来源各抽 20 行样本，人工看一下列名。

你需要先得到一个文件：

```text
rules/source_mapping.md
```

内容类似：

```markdown
# wechat.csv
交易时间 -> txn_date + txn_time
交易类型 -> txn_type
交易对方 -> merchant
收/支 -> direction
金额(元) -> amount
支付方式 -> account_name
当前状态 -> status
交易单号 -> source_row_id

# alipay.csv
交易创建时间 -> txn_date + txn_time
商品名称 -> merchant
收/支 -> direction
金额 -> amount
账户名称 -> account_name
交易分类 -> txn_type
备注 -> remark
交易号 -> source_row_id

# cmb.csv
交易日期 -> txn_date
交易时间 -> txn_time
借贷标志 -> direction
交易金额 -> amount
摘要 -> remark
对方户名/商户 -> counterparty
账号 -> account_name
流水号 -> source_row_id
```

### 第二步：先统一成一份 normalized CSV

也就是每个来源先各自产出：

- `normalized/wechat_normalized.csv`
    
- `normalized/alipay_normalized.csv`
    
- `normalized/cmb_normalized.csv`
    

### 第三步：再做对账匹配

把这些 normalized 文件合并进一个中间表，再根据上面的规则打标签：

- `keep`
    
- `drop_duplicate`
    
- `internal_transfer`
    
- `review`
    

### 第四步：产出最终表

最后只保留：

- `keep`
    
- 并且不是 `internal_transfer`
    

得到：

```text
output/cash_pool_2026-01-01_to_today.csv
```

---

## 你可以直接给 `wallet-reconcile` 的第一条任务

等你建好 agent 后，先不要把所有 CSV 一把塞进去。  
先做一个小样本测试。

你在这个 agent 里给它一条这样的指令：

```text
我正在做零钱池对账。
请先不要分析消费，也不要做理财建议。
你的任务只有两步：

1. 阅读我提供的 4 份 CSV 样本，帮我识别每个来源的列名含义，并输出统一字段映射表
2. 为“微信/支付宝 与 银行卡镜像扣款”、“银行卡之间内部转账”设计去重与排除规则

统一字段目标为：
source,source_file,source_row_id,txn_date,txn_time,amount,direction,account_name,counterparty,merchant,channel,txn_type,remark,balance,currency

输出格式：
A. 每个来源的字段映射表
B. 匹配规则列表
C. 需要人工确认的模糊点
```

这一步非常适合 agent 做，因为它擅长“看表头、归一语义、写规则说明”。

---

## 我对“是不是要直接用 agent 来处理”的最终建议

**要用，但不要只用 agent。**

最稳的分工是：

### 规则/脚本负责

- 统一日期时间格式
    
- 金额正负规范
    
- 金额与时间窗口匹配
    
- 内部转账识别
    
- 去重打标签
    
- 输出最终 CSV
    

### agent 负责

- 字段映射
    
- 规则设计草案
    
- 模糊记录复核
    
- 商户分类
    
- 月度/季度分析
    
- 写入 Obsidian 月报
    

这才是长期可用的方案。

---

## 你现在就可以开始的最小闭环

今天先做这 4 件事：

1. 建目录
    
2. 建 `wallet-reconcile` agent
    
3. 从每个来源各挑 20 行做样本
    
4. 让 agent 先输出字段映射和匹配规则，不急着跑全量
    

---

## 我建议你下一步这样继续

你把这些 CSV 先各取前 20–30 行，去掉明显隐私后上传给我。  
我下一轮可以直接帮你做两样东西：

**1. 统一字段映射表**  
**2. 第一版去重/内部转账匹配规则**

然后我们再继续下一步，变成真正可跑的“零钱池对账流水线”。