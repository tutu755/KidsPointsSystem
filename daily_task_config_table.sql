-- 创建每日任务配置表
-- daily_task_config table for tracking daily available tasks

CREATE TABLE IF NOT EXISTS daily_task_config (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    child_id BIGINT NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    task_name TEXT NOT NULL,
    task_type TEXT NOT NULL, -- 'daily', 'behavior', 'penalties'
    points INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- 确保每个孩子每天每个任务只有一条配置记录
    UNIQUE(child_id, date, task_name)
);

-- 创建索引提高查询性能
CREATE INDEX IF NOT EXISTS idx_daily_task_config_child_date 
ON daily_task_config(child_id, date);

CREATE INDEX IF NOT EXISTS idx_daily_task_config_date 
ON daily_task_config(date);

CREATE INDEX IF NOT EXISTS idx_daily_task_config_active 
ON daily_task_config(child_id, date, is_active);

-- 启用RLS (Row Level Security)
ALTER TABLE daily_task_config ENABLE ROW LEVEL SECURITY;

-- 创建RLS策略
CREATE POLICY "users_can_manage_child_task_config" ON daily_task_config
FOR ALL USING (
  child_id IN (
    SELECT id FROM children WHERE parent_id = auth.uid()
  )
);

-- 创建函数：自动记录每日任务配置
CREATE OR REPLACE FUNCTION record_daily_task_config(
    p_child_id BIGINT,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    task_record RECORD;
    inserted_count INTEGER := 0;
BEGIN
    -- 获取该孩子当前的所有活跃任务
    FOR task_record IN
        SELECT name, type, points
        FROM tasks 
        WHERE child_id = p_child_id 
        AND type != 'redeem' -- 排除奖励兑换
    LOOP
        -- 插入或更新任务配置（如果已存在则跳过）
        INSERT INTO daily_task_config (
            child_id,
            date,
            task_name,
            task_type,
            points,
            is_active
        )
        VALUES (
            p_child_id,
            p_date,
            task_record.name,
            task_record.type,
            task_record.points,
            true
        )
        ON CONFLICT (child_id, date, task_name) 
        DO UPDATE SET
            task_type = EXCLUDED.task_type,
            points = EXCLUDED.points,
            is_active = EXCLUDED.is_active;
        
        inserted_count := inserted_count + 1;
    END LOOP;
    
    RETURN 'Recorded ' || inserted_count || ' task configurations for date ' || p_date;
END;
$$;

-- 创建函数：计算准确的完成率
CREATE OR REPLACE FUNCTION get_accurate_completion_rate(
    p_child_id BIGINT,
    p_date DATE
)
RETURNS TABLE (
    total_available_tasks INTEGER,
    completed_tasks INTEGER,
    completion_rate NUMERIC,
    total_possible_points INTEGER,
    earned_points INTEGER,
    point_completion_rate NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH available_tasks AS (
        SELECT 
            COUNT(*) as total_tasks,
            SUM(CASE WHEN points > 0 THEN 1 ELSE 0 END) as positive_tasks,
            SUM(CASE WHEN points > 0 THEN points ELSE 0 END) as max_points
        FROM daily_task_config
        WHERE child_id = p_child_id 
        AND date = p_date 
        AND is_active = true
    ),
    completed_today AS (
        SELECT 
            COUNT(*) as done_tasks,
            SUM(CASE WHEN points > 0 THEN 1 ELSE 0 END) as positive_done,
            SUM(CASE WHEN points > 0 THEN points ELSE 0 END) as earned_pts
        FROM history h
        JOIN daily_task_config dtc ON (
            dtc.child_id = h.child_id 
            AND dtc.date = h.date::DATE 
            AND dtc.task_name = h.task
            AND dtc.is_active = true
        )
        WHERE h.child_id = p_child_id 
        AND h.date = p_date
        AND h.type != 'redeem'
    )
    SELECT 
        COALESCE(at.positive_tasks, 0)::INTEGER as total_available_tasks,
        COALESCE(ct.positive_done, 0)::INTEGER as completed_tasks,
        CASE 
            WHEN COALESCE(at.positive_tasks, 0) > 0 
            THEN ROUND(COALESCE(ct.positive_done, 0)::NUMERIC / at.positive_tasks * 100, 2)
            ELSE 0 
        END as completion_rate,
        COALESCE(at.max_points, 0)::INTEGER as total_possible_points,
        COALESCE(ct.earned_pts, 0)::INTEGER as earned_points,
        CASE 
            WHEN COALESCE(at.max_points, 0) > 0 
            THEN ROUND(COALESCE(ct.earned_pts, 0)::NUMERIC / at.max_points * 100, 2)
            ELSE 0 
        END as point_completion_rate
    FROM available_tasks at
    CROSS JOIN completed_today ct;
END;
$$;

-- 创建函数：批量补录历史任务配置
CREATE OR REPLACE FUNCTION backfill_task_config(
    p_child_id BIGINT,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    date_cursor DATE;
    total_days INTEGER := 0;
BEGIN
    date_cursor := p_start_date;
    
    WHILE date_cursor <= p_end_date LOOP
        -- 为每一天记录任务配置
        PERFORM record_daily_task_config(p_child_id, date_cursor);
        total_days := total_days + 1;
        date_cursor := date_cursor + INTERVAL '1 day';
    END LOOP;
    
    RETURN 'Backfilled task configuration for ' || total_days || ' days from ' || p_start_date || ' to ' || p_end_date;
END;
$$;

-- 创建触发器：当任务发生变化时自动记录配置
CREATE OR REPLACE FUNCTION trigger_record_task_config()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
BEGIN
    -- 当有新的历史记录插入时，自动记录当天的任务配置
    IF TG_OP = 'INSERT' THEN
        PERFORM record_daily_task_config(NEW.child_id, NEW.date::DATE);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- 创建触发器
DROP TRIGGER IF EXISTS trigger_auto_record_config ON history;
CREATE TRIGGER trigger_auto_record_config
    AFTER INSERT ON history
    FOR EACH ROW
    EXECUTE FUNCTION trigger_record_task_config();

-- 创建视图：便于查询准确的统计数据
CREATE OR REPLACE VIEW accurate_daily_stats AS
SELECT 
    c.name as child_name,
    dtc.child_id,
    dtc.date,
    COUNT(*) as available_tasks,
    COUNT(CASE WHEN dtc.points > 0 THEN 1 END) as positive_tasks,
    SUM(CASE WHEN dtc.points > 0 THEN dtc.points ELSE 0 END) as max_possible_points,
    COUNT(h.id) as completed_tasks,
    COUNT(CASE WHEN h.points > 0 THEN 1 END) as positive_completed,
    SUM(CASE WHEN h.points > 0 THEN h.points ELSE 0 END) as earned_points,
    CASE 
        WHEN COUNT(CASE WHEN dtc.points > 0 THEN 1 END) > 0 
        THEN ROUND(COUNT(CASE WHEN h.points > 0 THEN 1 END)::NUMERIC / COUNT(CASE WHEN dtc.points > 0 THEN 1 END) * 100, 2)
        ELSE 0 
    END as task_completion_rate,
    CASE 
        WHEN SUM(CASE WHEN dtc.points > 0 THEN dtc.points ELSE 0 END) > 0 
        THEN ROUND(SUM(CASE WHEN h.points > 0 THEN h.points ELSE 0 END)::NUMERIC / SUM(CASE WHEN dtc.points > 0 THEN dtc.points ELSE 0 END) * 100, 2)
        ELSE 0 
    END as point_completion_rate
FROM daily_task_config dtc
JOIN children c ON c.id = dtc.child_id
LEFT JOIN history h ON (
    h.child_id = dtc.child_id 
    AND h.date = dtc.date 
    AND h.task = dtc.task_name 
    AND h.type != 'redeem'
)
WHERE dtc.is_active = true
GROUP BY c.name, dtc.child_id, dtc.date
ORDER BY dtc.child_id, dtc.date DESC;

-- 创建完成提示
SELECT 'daily_task_config table created successfully!' as message,
       'Use record_daily_task_config() to track daily available tasks' as usage,
       'Use get_accurate_completion_rate() for precise completion calculations' as feature; 