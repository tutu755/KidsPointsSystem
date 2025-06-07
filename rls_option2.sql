-- 选项2：修复RLS策略（推荐的安全方案）
-- 执行前请确保选项1已经让系统正常工作

-- 重新启用RLS
ALTER TABLE history ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE children ENABLE ROW LEVEL SECURITY;

-- 删除现有有问题的策略
DROP POLICY IF EXISTS "users_can_manage_own_history" ON history;
DROP POLICY IF EXISTS "users_can_manage_own_tasks" ON tasks;
DROP POLICY IF EXISTS "users_can_manage_own_rewards" ON rewards;
DROP POLICY IF EXISTS "users_can_manage_own_children" ON children;

-- 创建新的正确策略
CREATE POLICY "users_can_manage_own_history" ON history
FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "users_can_manage_own_tasks" ON tasks
FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "users_can_manage_own_rewards" ON rewards
FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "users_can_manage_own_children" ON children
FOR ALL USING (auth.uid() = parent_id); 