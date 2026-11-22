
-- Eleven11: Default seed data
-- Safe to run more than once without duplicating records.

-- 1. Motivation categories
INSERT INTO public.motivation_categories (name, description)
SELECT v.name, v.description
FROM (VALUES
    ('Discipline', 'Build consistency and self-control'),
    ('Focus', 'Improve concentration and avoid distractions'),
    ('Success', 'Stay inspired to achieve your ambitions'),
    ('Confidence', 'Build belief in yourself'),
    ('Resilience', 'Keep going through difficult times'),
    ('Growth', 'Learn, improve and become better'),
    ('Health', 'Prioritize physical and mental wellness'),
    ('Productivity', 'Make meaningful progress every day')
) AS v(name, description)
WHERE NOT EXISTS (
    SELECT 1 FROM public.motivation_categories c
    WHERE lower(c.name) = lower(v.name)
);

-- 2. Global goal categories
INSERT INTO public.goal_categories (user_id, name)
SELECT NULL, v.name
FROM (VALUES
    ('Personal'),
    ('Career'),
    ('Education'),
    ('Health & Fitness'),
    ('Finance'),
    ('Relationships'),
    ('Learning'),
    ('Other')
) AS v(name)
WHERE NOT EXISTS (
    SELECT 1 FROM public.goal_categories c
    WHERE c.user_id IS NULL
      AND lower(c.name) = lower(v.name)
);

-- 3. Achievements
INSERT INTO public.achievements (name, description, points, is_active)
SELECT v.name, v.description, v.points, true
FROM (VALUES
    ('First Step', 'Create your first goal', 10),
    ('Getting Started', 'Complete your first task', 10),
    ('Consistency', 'Maintain a 3-day streak', 20),
    ('One Week Strong', 'Maintain a 7-day streak', 50),
    ('Goal Getter', 'Complete your first goal', 50),
    ('Task Master', 'Complete 50 tasks', 100),
    ('Unstoppable', 'Maintain a 30-day streak', 200)
) AS v(name, description, points)
WHERE NOT EXISTS (
    SELECT 1 FROM public.achievements a
    WHERE lower(a.name) = lower(v.name)
);

-- 4. Motivational quotes linked to categories
INSERT INTO public.quotes (content, author, category_id, is_active)
SELECT v.content, 'Eleven11', c.id, true
FROM (VALUES
    ('Discipline is choosing your long-term goals over temporary comfort.', 'Discipline'),
    ('Small progress every day creates remarkable results.', 'Growth'),
    ('Your future is shaped by what you do today.', 'Success'),
    ('Focus on progress, not perfection.', 'Focus'),
    ('You are stronger than the obstacles in front of you.', 'Resilience'),
    ('Believe in your ability to learn and improve.', 'Confidence'),
    ('Take care of your health; it supports everything you do.', 'Health'),
    ('Start where you are. Use what you have. Do what you can.', 'Productivity'),
    ('Consistency turns effort into achievement.', 'Discipline'),
    ('Every meaningful achievement begins with one small step.', 'Success')
) AS v(content, category_name)
JOIN public.motivation_categories c
    ON lower(c.name) = lower(v.category_name)
WHERE NOT EXISTS (
    SELECT 1 FROM public.quotes q
    WHERE q.content = v.content
);
