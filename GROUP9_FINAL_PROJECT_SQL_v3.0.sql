-- ================================================================
-- Query 1: Safety Ratings by Body Style
-- ================================================================
-- Calculates average star ratings (overall, frontal, side, rollover)
-- grouped by vehicle body style to identify which body types
-- perform best/worst in NHTSA crash testing.
-- ================================================================

SELECT
    BODY_STYLE,
    COUNT(*) AS VEHICLES_RATED,
    ROUND(AVG(OVERALL_STARS), 2) AS AVG_OVERALL_STARS,
    ROUND(AVG(OVERALL_FRNT_STARS), 2) AS AVG_FRONTAL_STARS,
    ROUND(AVG(OVERALL_SIDE_STARS), 2) AS AVG_SIDE_STARS,
    ROUND(AVG(ROLLOVER_STARS), 2) AS AVG_ROLLOVER_STARS,
    ROUND(AVG(ROLLOVER_POSSIBILITY), 2) AS AVG_ROLLOVER_PROBABILITY
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_SAFETY
WHERE OVERALL_STARS IS NOT NULL
GROUP BY BODY_STYLE
HAVING COUNT(*) >= 5
ORDER BY AVG_OVERALL_STARS DESC;

-- ================================================================
-- Query 2: Safety Rating Trends Year-over-Year (WINDOW FUNCTIONS)
-- ================================================================
-- Uses multiple window functions to analyze safety rating trends:
-- - LAG() for year-over-year change detection
-- - AVG() OVER ROWS for 3-year rolling average (smoothing)
-- - PERCENT_RANK() for relative safety positioning
-- - SUM() OVER UNBOUNDED PRECEDING for cumulative high ratings
-- - RANK() for within-year ranking
-- ================================================================

SELECT
    MAKE,
    MODEL,
    MODEL_YR,
    OVERALL_STARS,
    ROLLOVER_POSSIBILITY,
    PERCENT_RANK() OVER (ORDER BY OVERALL_STARS DESC) AS SAFETY_PERCENTILE,
    LAG(OVERALL_STARS) OVER (PARTITION BY MAKE ORDER BY MODEL_YR) AS PREV_YEAR_STARS,
    OVERALL_STARS - LAG(OVERALL_STARS) OVER (PARTITION BY MAKE ORDER BY MODEL_YR) AS STAR_CHANGE,
    AVG(OVERALL_STARS) OVER (PARTITION BY MAKE ORDER BY MODEL_YR ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ROLLING_3YR_AVG,
    RANK() OVER (PARTITION BY MODEL_YR ORDER BY OVERALL_STARS DESC) AS RANK_IN_YEAR,
    COUNT(*) OVER (PARTITION BY MAKE) AS TOTAL_MODELS_BY_MAKE,
    SUM(CASE WHEN OVERALL_STARS >= 4 THEN 1 ELSE 0 END) OVER (PARTITION BY MAKE ORDER BY MODEL_YR ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CUMULATIVE_HIGH_RATINGS
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_SAFETY
WHERE OVERALL_STARS IS NOT NULL
ORDER BY MAKE, MODEL_YR;

-- ================================================================
-- Query 3: Ranking Makes by Consumer Complaints
-- ================================================================
-- Aggregates all consumer complaints by vehicle make to produce
-- a ranked leaderboard of the top 20 most-complained-about brands.
-- Includes death/injury totals and a normalized death rate per
-- complaint to distinguish volume from severity.
-- ================================================================

SELECT
    MAKETXT AS MAKE,
    COUNT(*) AS TOTAL_COMPLAINTS,
    SUM(DEATHS) AS TOTAL_DEATHS,
    SUM(INJURED) AS TOTAL_INJURIES,
    SUM(CASE WHEN CRASH = 'Y' THEN 1 ELSE 0 END) AS CRASH_COUNT,
    SUM(CASE WHEN FIRE = 'Y' THEN 1 ELSE 0 END) AS FIRE_COUNT,
    ROUND(SUM(DEATHS) * 100.0 / NULLIF(COUNT(*), 0), 4) AS DEATH_RATE_PER_COMPLAINT
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS
GROUP BY MAKETXT
ORDER BY TOTAL_COMPLAINTS DESC
LIMIT 20;

-- ================================================================
-- Query 4: Complaint Rankings Over Time (WINDOW FUNCTIONS)
-- ================================================================
-- Uses RANK() to determine each make's complaint position per year
-- and SUM() OVER to compute a running total of complaints.
-- Reveals which manufacturers consistently lead in complaints
-- and how their ranking shifts year over year.
-- ================================================================

SELECT
    MAKETXT AS MAKE,
    YEARTXT AS MODEL_YEAR,
    COUNT(DISTINCT CMPLID) AS COMPLAINTS,
    SUM(COUNT(DISTINCT CMPLID)) OVER (PARTITION BY MAKETXT ORDER BY YEARTXT) AS RUNNING_TOTAL_COMPLAINTS,
    RANK() OVER (PARTITION BY YEARTXT ORDER BY COUNT(DISTINCT CMPLID) DESC) AS RANK_IN_YEAR
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS
GROUP BY MAKETXT, YEARTXT
ORDER BY YEARTXT, RANK_IN_YEAR;

-- ================================================================
-- Query 5: What Breaks and Who Makes It (GROUP BY ROLLUP)
-- ================================================================
-- Uses ROLLUP to create a hierarchical summary of complaints:
-- Make > Component, with automatic subtotals at each level.
-- Shows both the detail (which components fail) and the big
-- picture (total complaints per make and grand total).
-- ================================================================

SELECT
    COALESCE(MAKETXT, '-- ALL MAKES --') AS MAKE,
    COALESCE(CDESCR, '-- ALL COMPONENTS --') AS COMPONENT,
    COUNT(*) AS COMPLAINT_COUNT,
    SUM(DEATHS) AS TOTAL_DEATHS,
    SUM(INJURED) AS TOTAL_INJURIES
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS
GROUP BY ROLLUP(MAKETXT, CDESCR)
ORDER BY MAKETXT NULLS LAST, COMPLAINT_COUNT DESC;

-- ================================================================
-- Query 6: Do Complaints Match Safety Ratings? (JOIN)
-- ================================================================
-- Joins complaints with safety ratings on make/model/year to test
-- whether vehicles with more complaints also have lower safety
-- ratings — exploring the link between consumer issues and
-- crash test performance.
-- ================================================================

SELECT
    c.MAKETXT AS MAKE,
    c.MODELTXT AS MODEL,
    c.YEARTXT AS MODEL_YEAR,
    COUNT(*) AS COMPLAINT_COUNT,
    SUM(c.DEATHS) AS TOTAL_DEATHS,
    SUM(c.INJURED) AS TOTAL_INJURIES,
    s.OVERALL_STARS,
    s.ROLLOVER_STARS
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS c
INNER JOIN BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_SAFETY s
    ON UPPER(c.MAKETXT) = UPPER(s.MAKE)
    AND UPPER(c.MODELTXT) = UPPER(s.MODEL)
    AND TRY_CAST(c.YEARTXT AS NUMBER) = s.MODEL_YR
GROUP BY c.MAKETXT, c.MODELTXT, c.YEARTXT, s.OVERALL_STARS, s.ROLLOVER_STARS
ORDER BY COMPLAINT_COUNT DESC;

-- ================================================================
-- Query 7: Which Cars Attract Regulatory Scrutiny?
-- ================================================================
-- Groups investigations by make/model/component to find which
-- specific vehicle configurations attract the most formal NHTSA
-- scrutiny. Related campaign counts show whether investigations
-- eventually led to recalls.
-- ================================================================

SELECT
    MAKE,
    MODEL,
    COMPNAME AS COMPONENT,
    COUNT(DISTINCT ACTION_NUMBER) AS INVESTIGATION_COUNT,
    COUNT(DISTINCT CAMPNO) AS RELATED_CAMPAIGNS,
    MIN(YEAR) AS EARLIEST_YEAR,
    MAX(YEAR) AS LATEST_YEAR
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_INVESTIGATIONS
GROUP BY MAKE, MODEL, COMPNAME
ORDER BY INVESTIGATION_COUNT DESC
LIMIT 20;

-- ================================================================
-- Query 8: Who Puts the Most Cars at Risk? (Recalls Ranking)
-- ================================================================
-- Deduplicates recall campaigns at the make level using QUALIFY
-- and ROW_NUMBER to prevent double-counting vehicles affected.
-- Produces the top 20 makes by total vehicles recalled, with
-- severity flags for catastrophic defects.
-- ================================================================

WITH campaign_level AS (
    SELECT
        CAMPNO,
        MAKETXT,
        POTAFF,
        COMPNAME,
        DO_NOT_DRIVE,
        PARK_OUTSIDE,
        ROW_NUMBER() OVER (PARTITION BY CAMPNO ORDER BY MAKETXT) AS rn
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CAMPNO, MAKETXT ORDER BY MODELTXT) = 1
)
SELECT
    MAKETXT AS MAKE,
    COUNT(DISTINCT CAMPNO) AS TOTAL_RECALLS,
    SUM(CASE WHEN rn = 1 THEN POTAFF ELSE 0 END) AS TOTAL_VEHICLES_AFFECTED,
    COUNT(DISTINCT COMPNAME) AS COMPONENTS_RECALLED,
    SUM(CASE WHEN DO_NOT_DRIVE = 'Y' THEN 1 ELSE 0 END) AS DO_NOT_DRIVE_RECALLS,
    SUM(CASE WHEN PARK_OUTSIDE = 'Y' THEN 1 ELSE 0 END) AS PARK_OUTSIDE_RECALLS
FROM campaign_level
GROUP BY MAKETXT
ORDER BY TOTAL_VEHICLES_AFFECTED DESC NULLS LAST
LIMIT 20;

-- ================================================================
-- Query 9: Recall Anatomy by Component × Make (GROUP BY CUBE)
-- ================================================================
-- Uses CUBE to generate all possible grouping combinations of
-- component and make. Produces: detail rows (component+make),
-- component subtotals (across all makes), make subtotals (across
-- all components), and the grand total.
-- ================================================================

SELECT
    COALESCE(COMPNAME, '-- ALL COMPONENTS --') AS COMPONENT,
    COALESCE(MAKETXT, '-- ALL MAKES --') AS MAKE,
    COUNT(DISTINCT CAMPNO) AS RECALL_COUNT,
    SUM(POTAFF) AS TOTAL_AFFECTED
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL
WHERE MAKETXT IN ('FORD', 'CHEVROLET', 'TOYOTA', 'HONDA', 'NISSAN')
GROUP BY CUBE(COMPNAME, MAKETXT)
ORDER BY TOTAL_AFFECTED DESC NULLS LAST;

-- ================================================================
-- Query 10: Recalls Linked to Investigations (JOIN)
-- ================================================================
-- Joins recalls with NHTSA investigations on campaign number to
-- identify which recalls triggered formal investigations. Shows
-- the relationship between recall severity and regulatory scrutiny.
-- ================================================================

SELECT
    r.MAKETXT AS MAKE,
    r.CAMPNO AS CAMPAIGN_NUMBER,
    r.COMPNAME AS RECALL_COMPONENT,
    r.POTAFF AS VEHICLES_AFFECTED,
    r.DESC_DEFECT,
    i.ACTION_NUMBER,
    i.SUBJECT AS INVESTIGATION_SUBJECT,
    i.SUMMARY AS INVESTIGATION_SUMMARY
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL r
INNER JOIN BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_INVESTIGATIONS i
    ON r.CAMPNO = i.CAMPNO
ORDER BY r.POTAFF DESC;

-- ================================================================
-- Query 11: The Full Pipeline — Complaints to Recalls (JOIN)
-- ================================================================
-- LEFT JOINs complaints to recalls on make/model/year to trace
-- which consumer-reported issues eventually led to formal recall
-- campaigns. Aggregates by make to show complaint volume, related
-- recalls, and severity metrics.
-- ================================================================

SELECT
    c.MAKETXT AS MAKE,
    COUNT(DISTINCT c.CMPLID) AS COMPLAINT_COUNT,
    COUNT(DISTINCT r.CAMPNO) AS RELATED_RECALLS,
    SUM(c.DEATHS) AS DEATHS_FROM_COMPLAINTS,
    SUM(c.INJURED) AS INJURIES_FROM_COMPLAINTS
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS c
LEFT JOIN BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL r
    ON UPPER(c.MAKETXT) = UPPER(r.MAKETXT)
    AND UPPER(c.MODELTXT) = UPPER(r.MODELTXT)
    AND c.YEARTXT = r.YEARTXT
WHERE c.MAKETXT IS NOT NULL
    AND UPPER(TRIM(c.MAKETXT)) NOT IN ('UNKNOWN', 'OTHER', '')
GROUP BY c.MAKETXT
HAVING COUNT(DISTINCT c.CMPLID) > 100
ORDER BY COMPLAINT_COUNT DESC
LIMIT 20;

-- ================================================================
-- Query 12: Complaints Hierarchy (ROLLUP)
-- ================================================================
-- Dynamically identifies the Top 5 complained-about makes, then
-- applies CASE WHEN component normalization and ROLLUP to produce
-- make subtotals, component subtotals, and a grand total. Crash
-- rate and casualty rate reveal true danger beyond raw volume.
-- ================================================================

WITH Dynamic_Top_Makes AS (
    SELECT MAKETXT
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS
    WHERE MAKETXT IS NOT NULL AND PROD_TYPE = 'V'
    GROUP BY MAKETXT
    ORDER BY COUNT(*) DESC
    LIMIT 5
),
Filtered_Complaints AS (
    SELECT 
        UPPER(TRIM(MAKETXT)) AS CLEAN_MAKE,
        DEATHS,
        INJURED,
        CRASH,
        CASE 
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('SERVICE BRAKES, HYDRAULIC', 'SERVICE BRAKES', 'SERVICE BRAKES, AIR', 'SERVICE BRAKES, ELECTRIC', 'PARKING BRAKE') THEN 'BRAKES & BRAKING SYSTEMS'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('ENGINE', 'ENGINE AND ENGINE COOLING') THEN 'ENGINE & COOLING'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('FUEL SYSTEM, GASOLINE', 'FUEL/PROPULSION SYSTEM', 'FUEL SYSTEM, OTHER', 'FUEL SYSTEM, DIESEL', 'HYBRID PROPULSION SYSTEM') THEN 'FUEL & PROPULSION SYSTEM'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('ELECTRONIC STABILITY CONTROL (ESC)', 'ELECTRONIC STABILITY CONTROL', 'TRACTION CONTROL SYSTEM') THEN 'ELECTRONIC STABILITY & TRACTION'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('VISIBILITY', 'VISIBILITY/WIPER') THEN 'VISIBILITY & WIPERS'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('EXTERIOR LIGHTING', 'INTERIOR LIGHTING') OR UPPER(TRIM(COMPDESC)) LIKE '%LIGHTING%' THEN 'LIGHTING SYSTEMS'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('TIRES', 'WHEELS') THEN 'TIRES & WHEELS'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('FORWARD COLLISION AVOIDANCE', 'LANE DEPARTURE', 'BACK OVER PREVENTION', 'COMMUNICATION') THEN 'ADAS & ADVANCED TECHNOLOGY'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('EQUIPMENT', 'EQUIPMENT ADAPTIVE/MOBILITY', 'TRAILER HITCHES') THEN 'EQUIPMENT & ACCESSORIES'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('CHILD SEAT', 'CHEST CLIP, BUCKLE, HARNESS', 'CARRY HANDLE, SHELL, BASE', 'TETHER, LOWER ANCHOR (ON CAR SEAT OR VEHICLE)', 'INSERT, PADDING') THEN 'CHILD SEAT & RESTRAINT EQUIPMENT'
            WHEN UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) IN ('UNKNOWN OR OTHER', 'OTHER/I AM NOT SURE', 'OTHER/UNKNOWN', 'NONE', '1', '120', 'FIRERELATED', '') OR SPLIT_PART(COMPDESC, ':', 1) IS NULL THEN 'OTHER / UNKNOWN'
            ELSE UPPER(TRIM(SPLIT_PART(COMPDESC, ':', 1))) 
        END AS CLEAN_COMPONENT
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS
    WHERE PROD_TYPE = 'V'
      AND UPPER(TRIM(MAKETXT)) IN (SELECT MAKETXT FROM Dynamic_Top_Makes)
)
SELECT
    CASE WHEN GROUPING(CLEAN_MAKE) = 1 THEN '--- ALL MAKES (GRAND TOTAL) ---' ELSE CLEAN_MAKE END AS VEHICLE_MAKE,
    CASE 
        WHEN GROUPING(CLEAN_MAKE) = 1 AND GROUPING(CLEAN_COMPONENT) = 1 THEN '--- ALL COMPONENTS (GRAND TOTAL) ---'
        WHEN GROUPING(CLEAN_COMPONENT) = 1 THEN '--- ALL COMPONENTS (SUBTOTAL) ---' 
        ELSE CLEAN_COMPONENT 
    END AS PRIMARY_COMPONENT,
    COUNT(*) AS TOTAL_COMPLAINTS,
    SUM(DEATHS) AS TOTAL_DEATHS,
    SUM(INJURED) AS TOTAL_INJURIES,
    COUNT_IF(CRASH = 'Y') AS TOTAL_CRASHES,
    ROUND(COUNT_IF(CRASH = 'Y') * 100.0 / NULLIF(COUNT(*), 0), 2) AS CRASH_RATE_PCT,
    ROUND((SUM(DEATHS) + SUM(INJURED)) * 100.0 / NULLIF(COUNT(*), 0), 2) AS CASUALTY_RATE_PCT
FROM Filtered_Complaints
GROUP BY ROLLUP(CLEAN_MAKE, CLEAN_COMPONENT)
ORDER BY GROUPING(CLEAN_MAKE) ASC, VEHICLE_MAKE ASC, GROUPING(CLEAN_COMPONENT) ASC, TOTAL_COMPLAINTS DESC;

-- ================================================================
-- Query 13: 3-Dimensional CUBE (Brand × Component × Recall Type)
-- ================================================================
-- Performs a 3-dimensional cross-tabulation using CUBE across
-- Brand, Component, and Recall Type simultaneously. Pre-aggregates
-- campaigns using MAX(POTAFF) to prevent vehicle double-counting,
-- then applies GROUPING() labels for readable subtotal rows.
-- ================================================================

WITH Dynamic_Top_Makes AS (
    SELECT MAKETXT
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS
    WHERE MAKETXT IS NOT NULL AND PROD_TYPE = 'V'
    GROUP BY MAKETXT
    ORDER BY COUNT(*) DESC
    LIMIT 5
),
Normalized_Recalls_Base AS (
    SELECT 
        UPPER(TRIM(MAKETXT)) AS CLEAN_MAKE,
        UPPER(TRIM(RCLTYPECD)) AS CLEAN_RECALL_TYPE,
        UPPER(TRIM(CAMPNO)) AS CLEAN_CAMPNO,
        POTAFF,
        CASE 
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('SERVICE BRAKES, HYDRAULIC', 'SERVICE BRAKES', 'SERVICE BRAKES, AIR', 'SERVICE BRAKES, ELECTRIC', 'PARKING BRAKE') THEN 'BRAKES & BRAKING SYSTEMS'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('ENGINE', 'ENGINE AND ENGINE COOLING') THEN 'ENGINE & COOLING'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('FUEL SYSTEM, GASOLINE', 'FUEL/PROPULSION SYSTEM', 'FUEL SYSTEM, OTHER', 'FUEL SYSTEM, DIESEL', 'HYBRID PROPULSION SYSTEM') THEN 'FUEL & PROPULSION SYSTEM'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('ELECTRONIC STABILITY CONTROL (ESC)', 'ELECTRONIC STABILITY CONTROL', 'TRACTION CONTROL SYSTEM') THEN 'ELECTRONIC STABILITY & TRACTION'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('VISIBILITY', 'VISIBILITY/WIPER') THEN 'VISIBILITY & WIPERS'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('EXTERIOR LIGHTING', 'INTERIOR LIGHTING') THEN 'LIGHTING SYSTEMS'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('TIRES', 'WHEELS') THEN 'TIRES & WHEELS'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('FORWARD COLLISION AVOIDANCE', 'LANE DEPARTURE', 'BACK OVER PREVENTION', 'COMMUNICATION') THEN 'ADAS & ADVANCED TECHNOLOGY'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('EQUIPMENT', 'EQUIPMENT ADAPTIVE/MOBILITY', 'TRAILER HITCHES') THEN 'EQUIPMENT & ACCESSORIES'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('CHILD SEAT', 'CHEST CLIP, BUCKLE, HARNESS', 'CARRY HANDLE, SHELL, BASE', 'TETHER, LOWER ANCHOR (ON CAR SEAT OR VEHICLE)', 'INSERT, PADDING') THEN 'CHILD SEAT & RESTRAINT EQUIPMENT'
            WHEN UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) IN ('UNKNOWN OR OTHER', 'OTHER/I AM NOT SURE', 'OTHER/UNKNOWN', 'NONE', '1', '120', 'FIRERELATED', '') OR COMPNAME IS NULL THEN 'OTHER / UNKNOWN'
            ELSE UPPER(TRIM(SPLIT_PART(COMPNAME, ':', 1))) 
        END AS CLEAN_COMPONENT
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL
    WHERE UPPER(TRIM(MAKETXT)) IN (SELECT MAKETXT FROM Dynamic_Top_Makes)
      AND RCLTYPECD IS NOT NULL AND RCLTYPECD != 'X'
),
PreAggregated_Recalls AS (
    SELECT 
        CLEAN_MAKE, CLEAN_COMPONENT, CLEAN_RECALL_TYPE, CLEAN_CAMPNO,
        MAX(POTAFF) AS CAMPAIGN_POTAFF
    FROM Normalized_Recalls_Base
    WHERE CLEAN_COMPONENT IS NOT NULL AND CLEAN_COMPONENT != ''
    GROUP BY 1, 2, 3, 4
)
SELECT
    CASE WHEN GROUPING(CLEAN_MAKE) = 1 THEN '--- ALL MAKES ---' ELSE CLEAN_MAKE END AS VEHICLE_MAKE,
    CASE WHEN GROUPING(CLEAN_COMPONENT) = 1 THEN '--- ALL COMPONENTS ---' ELSE CLEAN_COMPONENT END AS PRIMARY_COMPONENT,
    CASE 
        WHEN GROUPING(CLEAN_RECALL_TYPE) = 1 THEN '--- ALL RECALL TYPES ---'
        WHEN CLEAN_RECALL_TYPE = 'V' THEN 'VEHICLE RECALL'
        WHEN CLEAN_RECALL_TYPE = 'E' THEN 'EQUIPMENT RECALL'
        WHEN CLEAN_RECALL_TYPE = 'T' THEN 'TIRE RECALL'
        WHEN CLEAN_RECALL_TYPE = 'C' THEN 'CHILD SEAT RECALL'
        ELSE CLEAN_RECALL_TYPE 
    END AS RECALL_CLASSIFICATION,
    COUNT(DISTINCT CLEAN_CAMPNO) AS TOTAL_RECALL_CAMPAIGNS,
    SUM(CAMPAIGN_POTAFF) AS TOTAL_VEHICLES_AFFECTED,
    ROUND(SUM(CAMPAIGN_POTAFF) * 1.0 / NULLIF(COUNT(DISTINCT CLEAN_CAMPNO), 0), 0) AS AVG_VEHICLES_PER_RECALL
FROM PreAggregated_Recalls
GROUP BY CUBE(CLEAN_MAKE, CLEAN_COMPONENT, CLEAN_RECALL_TYPE)
ORDER BY GROUPING(CLEAN_MAKE) ASC, GROUPING(CLEAN_COMPONENT) ASC, GROUPING(CLEAN_RECALL_TYPE) ASC, TOTAL_VEHICLES_AFFECTED DESC NULLS LAST
LIMIT 40;

-- ================================================================
-- Query 14: Above-Average Consumer Complaint Benchmark
-- ================================================================
-- Uses HAVING with a dynamic subquery to identify only brands
-- whose total complaint count exceeds the national per-brand
-- average. Includes Crash Rate % and Casualty Rate % to separate
-- volume effects (popular cars) from genuine danger signals.
-- ================================================================

WITH Cleaned_Complaints_Base AS (
    SELECT 
        REPLACE(UPPER(TRIM(MAKETXT)), '-', ' ') AS CLEAN_MAKE,
        DEATHS, INJURED, CRASH
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS
    WHERE MAKETXT IS NOT NULL AND PROD_TYPE = 'V' AND UPPER(TRIM(MAKETXT)) != 'UNKNOWN'
)
SELECT
    CLEAN_MAKE AS VEHICLE_MAKE,
    COUNT(*) AS TOTAL_COMPLAINTS,
    (
        SELECT ROUND(AVG(BRAND_VOLUME), 0)
        FROM (SELECT COUNT(*) AS BRAND_VOLUME FROM Cleaned_Complaints_Base GROUP BY CLEAN_MAKE)
    ) AS NATIONAL_BRAND_AVERAGE,
    SUM(DEATHS) AS TOTAL_DEATHS,
    SUM(INJURED) AS TOTAL_INJURIES,
    COUNT_IF(CRASH = 'Y') AS TOTAL_CRASHES,
    ROUND(COUNT_IF(CRASH = 'Y') * 100.0 / NULLIF(COUNT(*), 0), 2) AS CRASH_RATE_PCT,
    ROUND((SUM(DEATHS) + SUM(INJURED)) * 100.0 / NULLIF(COUNT(*), 0), 2) AS CASUALTY_RATE_PCT
FROM Cleaned_Complaints_Base
GROUP BY CLEAN_MAKE
HAVING COUNT(*) > (
    SELECT AVG(BRAND_VOLUME)
    FROM (SELECT COUNT(*) AS BRAND_VOLUME FROM Cleaned_Complaints_Base GROUP BY CLEAN_MAKE)
)
ORDER BY TOTAL_COMPLAINTS DESC;

-- ================================================================
-- Query 15: Laboratory Failure → Recall Matching (EXISTS)
-- ================================================================
-- Uses a correlated EXISTS subquery to find recall campaigns
-- targeting vehicles that scored ≤2 stars in NHTSA crash tests.
-- Applies CASE WHEN component normalization and campaign-level
-- MAX(POTAFF) deduplication for accurate vehicle counts.
-- ================================================================

WITH Deduplicated_Worst_Recalls AS (
    SELECT 
        UPPER(TRIM(r.MAKETXT)) AS VEHICLE_MAKE,
        UPPER(TRIM(r.MODELTXT)) AS VEHICLE_MODEL,
        TRY_CAST(REGEXP_REPLACE(r.YEARTXT, '[^0-9]', '') AS NUMBER) AS CLEAN_YEAR,
        UPPER(TRIM(r.CAMPNO)) AS UNIQUE_CAMPNO,
        r.POTAFF,
        CASE 
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('SERVICE BRAKES, HYDRAULIC', 'SERVICE BRAKES', 'SERVICE BRAKES, AIR', 'SERVICE BRAKES, ELECTRIC', 'PARKING BRAKE') THEN 'BRAKES & BRAKING SYSTEMS'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('ENGINE', 'ENGINE AND ENGINE COOLING') THEN 'ENGINE & COOLING'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('FUEL SYSTEM, GASOLINE', 'FUEL/PROPULSION SYSTEM', 'FUEL SYSTEM, OTHER', 'FUEL SYSTEM, DIESEL', 'HYBRID PROPULSION SYSTEM') THEN 'FUEL & PROPULSION SYSTEM'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('ELECTRONIC STABILITY CONTROL (ESC)', 'ELECTRONIC STABILITY CONTROL', 'TRACTION CONTROL SYSTEM') THEN 'ELECTRONIC STABILITY & TRACTION'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('VISIBILITY', 'VISIBILITY/WIPER') THEN 'VISIBILITY & WIPERS'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('EXTERIOR LIGHTING', 'INTERIOR LIGHTING') OR UPPER(TRIM(r.COMPNAME)) LIKE '%LIGHTING%' THEN 'LIGHTING SYSTEMS'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('TIRES', 'WHEELS') THEN 'TIRES & WHEELS'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('FORWARD COLLISION AVOIDANCE', 'LANE DEPARTURE', 'BACK OVER PREVENTION', 'COMMUNICATION') THEN 'ADAS & ADVANCED TECHNOLOGY'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('EQUIPMENT', 'EQUIPMENT ADAPTIVE/MOBILITY', 'TRAILER HITCHES') THEN 'EQUIPMENT & ACCESSORIES'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('CHILD SEAT', 'CHEST CLIP, BUCKLE, HARNESS', 'CARRY HANDLE, SHELL, BASE', 'TETHER, LOWER ANCHOR (ON CAR SEAT OR VEHICLE)', 'INSERT, PADDING') THEN 'CHILD SEAT & RESTRAINT EQUIPMENT'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('UNKNOWN OR OTHER', 'OTHER/I AM NOT SURE', 'OTHER/UNKNOWN', 'NONE', '1', '120', 'FIRERELATED', '') OR r.COMPNAME IS NULL THEN 'OTHER / UNKNOWN'
            ELSE UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) 
        END AS CLEAN_COMPONENT
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL r
    WHERE EXISTS (
        SELECT 1 
        FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_SAFETY s
        WHERE UPPER(TRIM(s.MAKE)) = UPPER(TRIM(r.MAKETXT))
          AND UPPER(TRIM(s.MODEL)) = UPPER(TRIM(r.MODELTXT))
          AND TRY_CAST(s.MODEL_YR AS NUMBER) = TRY_CAST(REGEXP_REPLACE(r.YEARTXT, '[^0-9]', '') AS NUMBER)
          AND s.OVERALL_STARS <= 2
    )
    AND r.COMPNAME IS NOT NULL AND r.COMPNAME != '' AND r.RCLTYPECD != 'X'
),
Campaign_Isolated_Recalls AS (
    SELECT VEHICLE_MAKE, VEHICLE_MODEL, CLEAN_YEAR, CLEAN_COMPONENT, UNIQUE_CAMPNO, MAX(POTAFF) AS TRUE_AFFECTED_VEHICLES
    FROM Deduplicated_Worst_Recalls
    GROUP BY 1, 2, 3, 4, 5
)
SELECT 
    VEHICLE_MAKE, VEHICLE_MODEL, CLEAN_YEAR AS MODEL_YEAR, CLEAN_COMPONENT AS PRIMARY_COMPONENT,
    COUNT(DISTINCT UNIQUE_CAMPNO) AS RECALL_CAMPAIGNS_ISSUED,
    SUM(TRUE_AFFECTED_VEHICLES) AS TOTAL_VEHICLES_RECALLED
FROM Campaign_Isolated_Recalls
GROUP BY 1, 2, 3, 4
ORDER BY TOTAL_VEHICLES_RECALLED DESC
LIMIT 25;

-- ================================================================
-- Query 16: Recalls for Low-Rated Vehicles (EXISTS + CASE)
-- ================================================================
-- Variant of Query 17 using TRY_CAST(YEARTXT AS NUMBER) directly
-- instead of REGEXP_REPLACE for year matching. Applies identical
-- component CASE WHEN mapping and campaign deduplication logic
-- to ensure structural parity across the analysis.
-- ================================================================

WITH Deduplicated_Worst_Recalls AS (
    SELECT 
        UPPER(TRIM(r.MAKETXT)) AS VEHICLE_MAKE,
        UPPER(TRIM(r.MODELTXT)) AS VEHICLE_MODEL,
        TRY_CAST(r.YEARTXT AS NUMBER) AS MODEL_YEAR,
        UPPER(TRIM(r.CAMPNO)) AS UNIQUE_CAMPNO,
        r.POTAFF,
        CASE 
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('SERVICE BRAKES, HYDRAULIC', 'SERVICE BRAKES', 'SERVICE BRAKES, AIR', 'SERVICE BRAKES, ELECTRIC', 'PARKING BRAKE') THEN 'BRAKES & BRAKING SYSTEMS'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('ENGINE', 'ENGINE AND ENGINE COOLING') THEN 'ENGINE & COOLING'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('FUEL SYSTEM, GASOLINE', 'FUEL/PROPULSION SYSTEM', 'FUEL SYSTEM, OTHER', 'FUEL SYSTEM, DIESEL', 'HYBRID PROPULSION SYSTEM') THEN 'FUEL & PROPULSION SYSTEM'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('ELECTRONIC STABILITY CONTROL (ESC)', 'ELECTRONIC STABILITY CONTROL', 'TRACTION CONTROL SYSTEM') THEN 'ELECTRONIC STABILITY & TRACTION'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('VISIBILITY', 'VISIBILITY/WIPER') THEN 'VISIBILITY & WIPERS'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('EXTERIOR LIGHTING', 'INTERIOR LIGHTING') THEN 'LIGHTING SYSTEMS'
            WHEN UPPER(TRIM(r.COMPNAME)) LIKE '%LIGHTING%' THEN 'LIGHTING SYSTEMS'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('TIRES', 'WHEELS') THEN 'TIRES & WHEELS'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('FORWARD COLLISION AVOIDANCE', 'LANE DEPARTURE', 'BACK OVER PREVENTION', 'COMMUNICATION') THEN 'ADAS & ADVANCED TECHNOLOGY'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('EQUIPMENT', 'EQUIPMENT ADAPTIVE/MOBILITY', 'TRAILER HITCHES') THEN 'EQUIPMENT & ACCESSORIES'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('CHILD SEAT', 'CHEST CLIP, BUCKLE, HARNESS', 'CARRY HANDLE, SHELL, BASE', 'TETHER, LOWER ANCHOR (ON CAR SEAT OR VEHICLE)', 'INSERT, PADDING') THEN 'CHILD SEAT & RESTRAINT EQUIPMENT'
            WHEN UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) IN ('UNKNOWN OR OTHER', 'OTHER/I AM NOT SURE', 'OTHER/UNKNOWN', 'NONE', '1', '120', 'FIRERELATED', '') OR r.COMPNAME IS NULL THEN 'OTHER / UNKNOWN'
            ELSE UPPER(TRIM(SPLIT_PART(r.COMPNAME, ':', 1))) 
        END AS CLEAN_COMPONENT
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL r
    WHERE EXISTS (
        SELECT 1 
        FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_SAFETY s
        WHERE UPPER(TRIM(s.MAKE)) = UPPER(TRIM(r.MAKETXT))
          AND UPPER(TRIM(s.MODEL)) = UPPER(TRIM(r.MODELTXT))
          AND TRY_CAST(s.MODEL_YR AS NUMBER) = TRY_CAST(r.YEARTXT AS NUMBER)
          AND s.OVERALL_STARS <= 2
    )
    AND r.COMPNAME IS NOT NULL AND r.COMPNAME != '' AND r.RCLTYPECD != 'X'
),
Campaign_Isolated_Recalls AS (
    SELECT 
        VEHICLE_MAKE, VEHICLE_MODEL, MODEL_YEAR, CLEAN_COMPONENT, UNIQUE_CAMPNO,
        MAX(POTAFF) AS TRUE_AFFECTED_VEHICLES
    FROM Deduplicated_Worst_Recalls
    GROUP BY 1, 2, 3, 4, 5
)
SELECT 
    VEHICLE_MAKE, VEHICLE_MODEL, MODEL_YEAR,
    CLEAN_COMPONENT AS PRIMARY_COMPONENT,
    COUNT(DISTINCT UNIQUE_CAMPNO) AS RECALL_CAMPAIGNS_ISSUED,
    SUM(TRUE_AFFECTED_VEHICLES) AS TOTAL_VEHICLES_RECALLED
FROM Campaign_Isolated_Recalls
GROUP BY 1, 2, 3, 4
ORDER BY TOTAL_VEHICLES_RECALLED DESC
LIMIT 25;

-- ================================================================
-- Query 17: Brand Safety Portfolio Risk Tiers (CTE + CASE WHEN)
-- ================================================================
-- Deduplicates campaigns at the brand level using MAX(POTAFF),
-- calculates the proportion of each brand's recall volume subject
-- to catastrophic directives (Do Not Drive / Park Outside), then
-- applies a tiered CASE WHEN to classify brands into risk buckets
-- for portfolio management decisions.
-- ================================================================

WITH UniqueCampaigns AS (
    SELECT 
        REPLACE(UPPER(TRIM(MAKETXT)), '-', ' ') AS CLEAN_MAKE,
        UPPER(TRIM(CAMPNO)) AS CLEAN_CAMPNO,
        MAX(POTAFF) AS CAMPAIGN_AFFECTED_VEHICLES,
        MAX(CASE WHEN UPPER(TRIM(DO_NOT_DRIVE)) IN ('Y', 'YES', '1', 'TRUE') THEN 1 ELSE 0 END) AS IS_DND,
        MAX(CASE WHEN UPPER(TRIM(PARK_OUTSIDE)) IN ('Y', 'YES', '1', 'TRUE') THEN 1 ELSE 0 END) AS IS_PO
    FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL
    WHERE MAKETXT IS NOT NULL AND RCLTYPECD = 'V'
      AND UPPER(TRIM(MAKETXT)) NOT IN ('UNKNOWN', 'OTHER', 'ALL', '')
    GROUP BY 1, 2
),
RecallSeverity AS (
    SELECT 
        CLEAN_MAKE AS VEHICLE_MAKE,
        COUNT(DISTINCT CLEAN_CAMPNO) AS TOTAL_SAFETY_CAMPAIGNS,
        SUM(CAMPAIGN_AFFECTED_VEHICLES) AS TOTAL_VEHICLES_RECALLED,
        SUM(CASE WHEN IS_DND = 1 OR IS_PO = 1 THEN CAMPAIGN_AFFECTED_VEHICLES ELSE 0 END) AS SEVERE_VEHICLES_RECALLED
    FROM UniqueCampaigns
    GROUP BY CLEAN_MAKE
    HAVING SUM(CAMPAIGN_AFFECTED_VEHICLES) > 500000
)
SELECT 
    VEHICLE_MAKE, TOTAL_SAFETY_CAMPAIGNS, TOTAL_VEHICLES_RECALLED, SEVERE_VEHICLES_RECALLED,
    ROUND((SEVERE_VEHICLES_RECALLED * 100.0) / NULLIF(TOTAL_VEHICLES_RECALLED, 0), 2) AS SEVERE_RECALL_PCT,
    CASE 
        WHEN SEVERE_VEHICLES_RECALLED = 0 AND TOTAL_VEHICLES_RECALLED > 5000000 THEN 'LOW RISK (Software / OTA Dominant Profile)'
        WHEN (SEVERE_VEHICLES_RECALLED * 1.0 / NULLIF(TOTAL_VEHICLES_RECALLED, 0)) > 0.10 THEN 'HIGH RISK (Monitor Closely - Capital Intensive)'
        WHEN (SEVERE_VEHICLES_RECALLED * 1.0 / NULLIF(TOTAL_VEHICLES_RECALLED, 0)) > 0.02 THEN 'MODERATE RISK (Standard Warranty Outlay)'
        ELSE 'LOW RISK (Routine Maintenance Variance)'
    END AS INVESTMENT_RISK_TIER
FROM RecallSeverity
ORDER BY SEVERE_RECALL_PCT DESC;

-- ================================================================
-- Query 18: Complaints + Safety Ratings (for Linear Regression)
-- ================================================================
-- Joins complaints with safety ratings on make/model/year to
-- create a training dataset with complaint counts, injuries,
-- deaths, and star ratings per vehicle configuration.
-- ================================================================

SELECT
    c.MAKETXT AS MAKE,
    c.MODELTXT AS MODEL,
    c.YEARTXT AS MODEL_YEAR,
    COUNT(*) AS COMPLAINT_COUNT,
    SUM(c.DEATHS) AS TOTAL_DEATHS,
    SUM(c.INJURED) AS TOTAL_INJURIES,
    s.OVERALL_STARS,
    s.ROLLOVER_STARS
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS c
INNER JOIN BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_SAFETY s
    ON UPPER(c.MAKETXT) = UPPER(s.MAKE)
    AND UPPER(c.MODELTXT) = UPPER(s.MODEL)
    AND TRY_CAST(c.YEARTXT AS NUMBER) = s.MODEL_YR
GROUP BY c.MAKETXT, c.MODELTXT, c.YEARTXT, s.OVERALL_STARS, s.ROLLOVER_STARS
ORDER BY COMPLAINT_COUNT DESC;

-- ================================================================
-- Query 19: Complaints Linked to Recalls (for Logistic Regression)
-- ================================================================
-- Full dataset of complaints joined to recalls without LIMIT,
-- providing complete training data for the logistic regression
-- model. Each row is a make with complaint volume, recall
-- campaigns, deaths, and injuries.
-- ================================================================

SELECT
    c.MAKETXT AS MAKE,
    COUNT(DISTINCT c.CMPLID) AS COMPLAINT_COUNT,
    COUNT(DISTINCT r.CAMPNO) AS RELATED_RECALLS,
    SUM(c.DEATHS) AS DEATHS_FROM_COMPLAINTS,
    SUM(c.INJURED) AS INJURIES_FROM_COMPLAINTS
FROM BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_COMPLAINTS c
LEFT JOIN BUSN32120_NHTSA_PROJECT.PUBLIC.NHTSA_RECALL r
    ON UPPER(c.MAKETXT) = UPPER(r.MAKETXT)
    AND UPPER(c.MODELTXT) = UPPER(r.MODELTXT)
    AND c.YEARTXT = r.YEARTXT
WHERE c.MAKETXT IS NOT NULL
    AND UPPER(TRIM(c.MAKETXT)) NOT IN ('UNKNOWN', 'OTHER', '')
GROUP BY c.MAKETXT
HAVING COUNT(DISTINCT c.CMPLID) > 10
ORDER BY COMPLAINT_COUNT DESC;