-- 创建奖励兑换统计表
-- rewards_completion_stats table for reward redemption statistics

CREATE TABLE IF NOT EXISTS rewards_completion_stats (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    child_id BIGINT NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    reward_name TEXT NOT NULL,
    redemption_count INTEGER NOT NULL DEFAULT 0,
    total_points_spent INTEGER NOT NULL DEFAULT 0,
    average_points_spent NUMERIC(10,2) NOT NULL DEFAULT 0,
    first_redemption_date DATE,
    last_redemption_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 创建索引提高查询性能
CREATE INDEX IF NOT EXISTS idx_rewards_completion_stats_child_id 
ON rewards_completion_stats(child_id);

CREATE INDEX IF NOT EXISTS idx_rewards_completion_stats_reward_name 
ON rewards_completion_stats(child_id, reward_name);

CREATE INDEX IF NOT EXISTS idx_rewards_completion_stats_redemption_count 
ON rewards_completion_stats(child_id, redemption_count DESC);

-- 启用RLS (Row Level Security)
ALTER TABLE rewards_completion_stats ENABLE ROW LEVEL SECURITY;

-- 创建RLS策略：用户只能访问自己孩子的奖励统计数据
CREATE POLICY "users_can_manage_child_reward_stats" ON rewards_completion_stats
FOR ALL USING (
  child_id IN (
    SELECT id FROM children WHERE parent_id = auth.uid()
  )
);

-- 创建或替换统计函数：更新奖励兑换统计
CREATE OR REPLACE FUNCTION update_reward_completion_stats()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
  -- 当有新的奖励兑换记录时，更新统计表
  IF NEW.type = 'redeem' THEN
    INSERT INTO rewards_completion_stats (
      child_id,
      reward_name,
      redemption_count,
      total_points_spent,
      average_points_spent,
      first_redemption_date,
      last_redemption_date
    )
    VALUES (
      NEW.child_id,
      REPLACE(NEW.task, '兑换', ''), -- 去掉"兑换"后缀
      1,
      ABS(NEW.points),
      ABS(NEW.points),
      NEW.date::DATE,
      NEW.date::DATE
    )
    ON CONFLICT (child_id, reward_name) 
    DO UPDATE SET
      redemption_count = rewards_completion_stats.redemption_count + 1,
      total_points_spent = rewards_completion_stats.total_points_spent + ABS(NEW.points),
      average_points_spent = ROUND(
        (rewards_completion_stats.total_points_spent + ABS(NEW.points))::NUMERIC / 
        (rewards_completion_stats.redemption_count + 1), 2
      ),
      last_redemption_date = GREATEST(rewards_completion_stats.last_redemption_date, NEW.date::DATE),
      updated_at = CURRENT_TIMESTAMP;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 创建触发器：在 history 表有新记录时自动更新统计
DROP TRIGGER IF EXISTS trigger_update_reward_stats ON history;
CREATE TRIGGER trigger_update_reward_stats
  AFTER INSERT ON history
  FOR EACH ROW
  EXECUTE FUNCTION update_reward_completion_stats();

-- 创建复合唯一约束，确保每个孩子的每个奖励只有一条统计记录
ALTER TABLE rewards_completion_stats 
ADD CONSTRAINT unique_child_reward 
UNIQUE (child_id, reward_name);

-- 创建或替换函数：手动重建奖励统计数据
CREATE OR REPLACE FUNCTION rebuild_reward_completion_stats(p_child_id BIGINT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  affected_rows INTEGER := 0;
BEGIN
  -- 清空现有统计数据（针对指定孩子或所有孩子）
  IF p_child_id IS NOT NULL THEN
    DELETE FROM rewards_completion_stats WHERE child_id = p_child_id;
  ELSE
    DELETE FROM rewards_completion_stats;
  END IF;
  
  -- 重新计算统计数据
  INSERT INTO rewards_completion_stats (
    child_id,
    reward_name,
    redemption_count,
    total_points_spent,
    average_points_spent,
    first_redemption_date,
    last_redemption_date
  )
  SELECT 
    h.child_id,
    REPLACE(h.task, '兑换', '') as reward_name,
    COUNT(*) as redemption_count,
    SUM(ABS(h.points)) as total_points_spent,
    ROUND(AVG(ABS(h.points)), 2) as average_points_spent,
    MIN(h.date::DATE) as first_redemption_date,
    MAX(h.date::DATE) as last_redemption_date
  FROM history h
  WHERE h.type = 'redeem' 
    AND h.child_id IS NOT NULL
    AND (p_child_id IS NULL OR h.child_id = p_child_id)
  GROUP BY h.child_id, REPLACE(h.task, '兑换', '')
  ORDER BY h.child_id, redemption_count DESC;
  
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  
  RETURN 'Successfully rebuilt reward completion stats for ' || affected_rows || ' reward types.';
END;
$$;

-- 创建视图：便于查询奖励统计数据
CREATE OR REPLACE VIEW reward_stats_view AS
SELECT 
  c.name as child_name,
  r.child_id,
  r.reward_name,
  r.redemption_count,
  r.total_points_spent,
  r.average_points_spent,
  r.first_redemption_date,
  r.last_redemption_date,
  r.updated_at
FROM rewards_completion_stats r
JOIN children c ON c.id = r.child_id
ORDER BY c.name, r.redemption_count DESC;

-- 执行初始数据填充
SELECT rebuild_reward_completion_stats() as initialization_result;

-- 创建完成提示
SELECT 'rewards_completion_stats table created successfully!' as message,
       'Run "SELECT * FROM reward_stats_view;" to view current data' as next_step; 