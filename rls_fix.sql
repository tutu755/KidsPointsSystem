-- 解决RLS策略问题的SQL命令
-- 选项1: 临时禁用所有表的RLS（快速解决方案）
ALTER TABLE history DISABLE ROW LEVEL SECURITY;
ALTER TABLE tasks DISABLE ROW LEVEL SECURITY;
ALTER TABLE rewards DISABLE ROW LEVEL SECURITY;
ALTER TABLE children DISABLE ROW LEVEL SECURITY;

-- 选项2: 修复RLS策略（推荐的安全方案）
-- 如果选择保持RLS，请取消注释以下命令：

/*
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
*/ 