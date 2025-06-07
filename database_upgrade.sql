-- 数据库升级脚本：支持多孩子独立数据
-- 执行顺序：先备份数据，再执行升级

-- 1. 为 history 表添加 child_id 字段
ALTER TABLE history ADD COLUMN child_id UUID REFERENCES children(id);

-- 2. 为现有的 history 记录设置默认的 child_id
-- 注意：这会将所有现有历史记录分配给第一个孩子
UPDATE history SET child_id = (
  SELECT id FROM children 
  WHERE parent_id = history.user_id 
  ORDER BY created_at ASC 
  LIMIT 1
) WHERE child_id IS NULL;

-- 3. 为 tasks 和 rewards 表也添加 child_id（每个孩子有独立的任务和奖励）
ALTER TABLE tasks ADD COLUMN child_id UUID REFERENCES children(id);
ALTER TABLE rewards ADD COLUMN child_id UUID REFERENCES children(id);

-- 4. 为现有的 tasks 记录设置默认的 child_id（分配给第一个孩子）
UPDATE tasks SET child_id = (
  SELECT id FROM children 
  WHERE parent_id = tasks.user_id 
  ORDER BY created_at ASC 
  LIMIT 1
) WHERE child_id IS NULL;

-- 5. 为现有的 rewards 记录设置默认的 child_id（分配给第一个孩子）
UPDATE rewards SET child_id = (
  SELECT id FROM children 
  WHERE parent_id = rewards.user_id 
  ORDER BY created_at ASC 
  LIMIT 1
) WHERE child_id IS NULL;

-- 6. 创建新的RLS策略来支持基于child_id的访问控制
-- 删除旧策略
DROP POLICY IF EXISTS "users_can_manage_own_history" ON history;
DROP POLICY IF EXISTS "users_can_manage_own_tasks" ON tasks;
DROP POLICY IF EXISTS "users_can_manage_own_rewards" ON rewards;

-- 创建新策略：用户可以管理自己孩子的数据
CREATE POLICY "users_can_manage_child_history" ON history
FOR ALL USING (
  auth.uid() IN (
    SELECT parent_id FROM children WHERE id = history.child_id
  )
);

CREATE POLICY "users_can_manage_child_tasks" ON tasks
FOR ALL USING (
  auth.uid() IN (
    SELECT parent_id FROM children WHERE id = tasks.child_id
  )
);

CREATE POLICY "users_can_manage_child_rewards" ON rewards
FOR ALL USING (
  auth.uid() IN (
    SELECT parent_id FROM children WHERE id = rewards.child_id
  )
);

-- 7. 创建索引提高查询性能
CREATE INDEX IF NOT EXISTS idx_history_child_id ON history(child_id);
CREATE INDEX IF NOT EXISTS idx_history_date_child ON history(date, child_id);
CREATE INDEX IF NOT EXISTS idx_tasks_child_id ON tasks(child_id);
CREATE INDEX IF NOT EXISTS idx_rewards_child_id ON rewards(child_id); 