-- 🚨 紧急修复脚本 - 完整解决多孩子系统问题
-- 使用说明：在 Supabase SQL 编辑器中逐个执行以下语句块

-- ===============================
-- 步骤 1: 禁用 RLS（确保能够修复数据）
-- ===============================
ALTER TABLE children DISABLE ROW LEVEL SECURITY;
ALTER TABLE history DISABLE ROW LEVEL SECURITY;  
ALTER TABLE tasks DISABLE ROW LEVEL SECURITY;
ALTER TABLE rewards DISABLE ROW LEVEL SECURITY;

-- ===============================
-- 步骤 2: 检查当前数据状态
-- ===============================
-- 检查用户和孩子关系
SELECT 
  u.email,
  c.id as child_id,
  c.name as child_name,
  c.created_at
FROM auth.users u
LEFT JOIN children c ON c.parent_id = u.id
ORDER BY u.email, c.created_at;

-- 检查各表的child_id状态
SELECT 
  'history' as table_name, 
  COUNT(*) as total_records, 
  COUNT(child_id) as with_child_id,
  COUNT(*) - COUNT(child_id) as null_child_id
FROM history
UNION ALL
SELECT 
  'tasks' as table_name, 
  COUNT(*) as total_records, 
  COUNT(child_id) as with_child_id,
  COUNT(*) - COUNT(child_id) as null_child_id
FROM tasks
UNION ALL
SELECT 
  'rewards' as table_name, 
  COUNT(*) as total_records, 
  COUNT(child_id) as with_child_id,
  COUNT(*) - COUNT(child_id) as null_child_id
FROM rewards;

-- ===============================
-- 步骤 3: 修复所有NULL的child_id记录
-- ===============================
-- 修复历史记录
UPDATE history 
SET child_id = (
  SELECT c.id 
  FROM children c 
  WHERE c.parent_id = history.user_id 
  ORDER BY c.created_at ASC 
  LIMIT 1
)
WHERE child_id IS NULL
AND user_id IN (SELECT DISTINCT parent_id FROM children);

-- 修复任务记录
UPDATE tasks
SET child_id = (
  SELECT c.id 
  FROM children c 
  WHERE c.parent_id = tasks.user_id 
  ORDER BY c.created_at ASC 
  LIMIT 1
)
WHERE child_id IS NULL
AND user_id IN (SELECT DISTINCT parent_id FROM children);

-- 修复奖励记录
UPDATE rewards
SET child_id = (
  SELECT c.id 
  FROM children c 
  WHERE c.parent_id = rewards.user_id 
  ORDER BY c.created_at ASC 
  LIMIT 1
)
WHERE child_id IS NULL
AND user_id IN (SELECT DISTINCT parent_id FROM children);

-- ===============================
-- 步骤 4: 验证修复结果
-- ===============================
-- 验证每个孩子的数据分布
SELECT 
  c.name as child_name,
  c.id as child_id,
  COUNT(DISTINCT h.id) as history_count,
  COUNT(DISTINCT t.id) as task_count, 
  COUNT(DISTINCT r.id) as reward_count,
  COALESCE(SUM(h.points), 0) as total_points
FROM children c
LEFT JOIN history h ON h.child_id = c.id
LEFT JOIN tasks t ON t.child_id = c.id  
LEFT JOIN rewards r ON r.child_id = c.id
GROUP BY c.id, c.name
ORDER BY c.created_at;

-- 检查是否还有NULL记录
SELECT 'Remaining NULL child_id records:' as status;
SELECT 
  'history' as table_name, 
  COUNT(*) as null_count 
FROM history 
WHERE child_id IS NULL
UNION ALL
SELECT 
  'tasks' as table_name, 
  COUNT(*) as null_count 
FROM tasks 
WHERE child_id IS NULL  
UNION ALL
SELECT 
  'rewards' as table_name, 
  COUNT(*) as null_count 
FROM rewards 
WHERE child_id IS NULL;

-- ===============================
-- 步骤 5: 设置安全的RLS策略
-- ===============================
-- 删除可能存在的旧策略
DROP POLICY IF EXISTS "users_can_manage_own_children" ON children;
DROP POLICY IF EXISTS "users_can_manage_own_history" ON history;
DROP POLICY IF EXISTS "users_can_manage_own_tasks" ON tasks;
DROP POLICY IF EXISTS "users_can_manage_own_rewards" ON rewards;
DROP POLICY IF EXISTS "users_can_manage_child_history" ON history;
DROP POLICY IF EXISTS "users_can_manage_child_tasks" ON tasks;
DROP POLICY IF EXISTS "users_can_manage_child_rewards" ON rewards;

-- 创建新的安全策略
-- Children 表策略
CREATE POLICY "users_can_manage_own_children" ON children
FOR ALL USING (auth.uid() = parent_id);

-- History 表策略
CREATE POLICY "users_can_manage_child_history" ON history
FOR ALL USING (
  child_id IN (
    SELECT id FROM children WHERE parent_id = auth.uid()
  )
);

-- Tasks 表策略  
CREATE POLICY "users_can_manage_child_tasks" ON tasks
FOR ALL USING (
  child_id IN (
    SELECT id FROM children WHERE parent_id = auth.uid()
  )
);

-- Rewards 表策略
CREATE POLICY "users_can_manage_child_rewards" ON rewards
FOR ALL USING (
  child_id IN (
    SELECT id FROM children WHERE parent_id = auth.uid()
  )
);

-- ===============================
-- 步骤 6: 重新启用RLS
-- ===============================
ALTER TABLE children ENABLE ROW LEVEL SECURITY;
ALTER TABLE history ENABLE ROW LEVEL SECURITY;  
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE rewards ENABLE ROW LEVEL SECURITY;

-- ===============================
-- 步骤 7: 最终验证
-- ===============================
-- 验证RLS是否正常工作
SELECT 'RLS Status Check:' as status;
SELECT schemaname, tablename, rowsecurity 
FROM pg_tables 
WHERE tablename IN ('children', 'history', 'tasks', 'rewards')
AND schemaname = 'public';

-- 显示完成信息
SELECT '🎉 Emergency Fix Completed!' as status,
       'Please refresh your frontend application.' as next_step; 