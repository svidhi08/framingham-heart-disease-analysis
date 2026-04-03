show databases;
use heart_disease_db;
select * from heart_disease_reports;


-- 1. find the volume of high-risk cases distributed by gender from our reporting table? 
select gender,count(*) as 'High Risk Count' from heart_disease_reports
where final_prediction='HIGH RISK' group by gender;
-- High-risk cases are almost evenly distributed across genders (285 vs 288), indicating gender alone may not be a strong differentiating factor

-- 2. "The medical team needs to see average risk scores across three specific age tiers. How would you bucket the 'age' column and aggregate the results?
WITH age_categorized AS (
    SELECT 
        CASE 
            WHEN age < 40 THEN 'Young(<40)'
            WHEN age BETWEEN 40 AND 60 THEN 'Middle Age(40-60)'
            ELSE 'Senior'
        END AS age_group,
        risk_probability
    FROM heart_disease_reports
)
SELECT 
    age_group,
    AVG(risk_probability) as avg_risk_score,
    COUNT(*) as patient_count
FROM age_categorized
GROUP BY age_group
ORDER BY avg_risk_score DESC;
-- Heart disease risk increases significantly with age, with seniors showing the highest risk (~0.71), followed by middle-aged (~0.44), and young individuals (~0.22)

-- 3. Is there a noticeable difference in cigarette consumption between predicted high-risk and low-risk patients?
select final_prediction,avg(cigs_per_day) as avg_daily_cigs from heart_disease_reports group by final_prediction order by avg_daily_cigs desc;
-- insight :High-risk individuals smoke more on average (~9.75/day) compared to low-risk individuals (~7.23/day), suggesting smoking is positively associated with higher heart disease risk

-- 4. Can you identify the top 5 patients who are labeled 'Low Risk' but have the highest glucose levels?
SELECT 
    age,
    glucose, 
    risk_probability 
FROM heart_disease_reports 
WHERE UPPER(final_prediction) = 'LOW RISK'
ORDER BY glucose DESC LIMIT 5;
-- Low-risk patients show unexpectedly high glucose levels (up to 115), indicating there can be hidden risk cases

-- 5. What percentage of the total patient population in our database suffers from hypertension?
select avg(prevalent_hyp)*100 as percent_hypertensive from heart_disease_reports;
-- Around 31% of patients suffer from hypertension, indicating a significant cardiovascular risk in the population

-- 6. How would you assign a numerical rank to every patient based on their risk probability, where the highest risk is ranked #1?
select risk_probability,rank() over (order by risk_probability desc) as risk_rank from heart_disease_reports limit 10;

-- 7. Within each gender group, rank patients by their Age-BP interaction score. Ensure ties receive the same rank.
-- select gender,age_bp_interaction,rank() over (partition by gender order by age_bp_interaction desc) as rank_within_gender from heart_disease_reports ORDER BY gender, rank_within_gender;
SELECT gender, age_bp_interaction, rank_within_gender
FROM (
  SELECT gender, age_bp_interaction,
         RANK() OVER (PARTITION BY gender ORDER BY age_bp_interaction DESC) as rank_within_gender 
  FROM heart_disease_reports
) t 
WHERE rank_within_gender <= 5
ORDER BY gender, rank_within_gender;
-- Patients with gender = 1 show a higher peak Age-BP interaction (140.58 vs 135.3), indicating stronger cardiovascular risk in that group

-- 8.We need to segment patients into four equal-sized groups based on their cholesterol levels. Which window function would you use?
SELECT tot_chol,
       NTILE(4) OVER (ORDER BY tot_chol) AS quartile
FROM heart_disease_reports
ORDER BY quartile, tot_chol
LIMIT 20;
-- OR
select * from(
select tot_chol,chol_group,row_number() over (partition by chol_group order by tot_chol) as rn
from(
select tot_chol,ntile(4) over (order by tot_chol) as chol_group from heart_disease_reports) t
) final where rn<5;
-- OR
WITH chol_groups AS (
    SELECT 
        tot_chol,
        NTILE(4) OVER (ORDER BY tot_chol) AS grp
    FROM heart_disease_reports
),
ranked AS (
    SELECT 
        tot_chol,
        grp,
        ROW_NUMBER() OVER (
            PARTITION BY grp 
            ORDER BY tot_chol
        ) AS rn
    FROM chol_groups
)
SELECT *
FROM ranked
WHERE rn <= 5;

-- 9. For every specific age, list patients and number them based on their risk level (highest to lowest).
with ranked as(
	select age,risk_probability,row_number() over (partition by age order by risk_probability desc) as rank_within_age
    from heart_disease_reports
)
select * from ranked order by age,risk_probability desc;

-- 10. Using a CTE, find all patients who have a risk probability strictly higher than the population average.
WITH avg_risk AS (
  SELECT AVG(risk_probability) AS avg_risk 
  FROM heart_disease_reports
)
SELECT h.* 
FROM heart_disease_reports h
CROSS JOIN avg_risk a  
WHERE h.risk_probability > a.avg_risk
LIMIT 100;  

-- 11. Show the average risk per education level side-by-side with the global average risk for comparison.
SELECT 
    education,
    AVG(risk_probability) AS avg_risk_per_education,
    (SELECT AVG(risk_probability) FROM heart_disease_reports) AS global_avg_risk
FROM heart_disease_reports
GROUP BY education;

-- 12. How can you compare a patient's risk to the patient analyzed immediately before them?
SELECT 
    analysis_date,
    risk_probability,
    LAG(risk_probability) OVER (
        ORDER BY analysis_date
    ) AS prev_risk,
    risk_probability - LAG(risk_probability) OVER (
        ORDER BY analysis_date
    ) AS risk_change
FROM heart_disease_reports;

-- 13. Identify patients in the top 10% of Age-BP interaction who were incorrectly flagged as 'Low Risk'
WITH ranked AS (
    SELECT *,
           NTILE(10) OVER (ORDER BY age_bp_interaction DESC) AS decile
    FROM heart_disease_reports
)
SELECT *
FROM ranked
WHERE decile = 1
AND LOWER(final_prediction) = 'low risk';
-- No high Age-BP patients are marked as Low Risk(All high BP-age patients → predicted HIGH RISK)
SELECT decile, final_prediction, COUNT(*)
FROM (
    SELECT 
        NTILE(10) OVER (ORDER BY age_bp_interaction DESC) AS decile,
        final_prediction
    FROM heart_disease_reports
) t
GROUP BY decile, final_prediction;

-- 14. Find patients with conflicting indicators
-- Low cholesterol + High BP + High Risk
SELECT tot_chol,sys_bp,final_prediction,risk_probability
FROM heart_disease_reports
WHERE tot_chol < 200 
  AND sys_bp > 140
  AND final_prediction = 'HIGH RISK'
ORDER BY risk_probability DESC;

-- 14. Moving average for risk trends
SELECT 
    analysis_date,
    risk_probability,
    AVG(risk_probability) OVER (
        ORDER BY analysis_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS risk_7day_avg
FROM heart_disease_reports
ORDER BY analysis_date;

-- 15. Gender-Age group risk comparison
WITH age_categorized AS (
    SELECT 
        gender,
        CASE 
            WHEN age < 40 THEN '<40'
            WHEN age BETWEEN 40 AND 60 THEN '40-60'
            ELSE '60+' 
        END AS age_group,
        risk_probability
    FROM heart_disease_reports
)
SELECT 
    gender,
    age_group,
    AVG(risk_probability) as avg_risk,
    COUNT(*) as patient_count
FROM age_categorized
GROUP BY gender, age_group
ORDER BY gender, age_group;
 DESCRIBE heart_disease_reports;
