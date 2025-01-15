-- Belows are the scripts  used for datasets comparison between world wide dishes (WWD) and worldcusines (WC)



/*
#1 Find unique food items in the WWD table, and overlapping food items betweenWC and WWD.

WWD has two columns:
- english_name (string)
- local_name (string)
These columns might contain more than one name for a dish.

WC has two columns:
- Name (string)
- Alias (a list of aliases formatted as [{'alias1': 'language1'}, {'alias2': 'language2'}, ...]).

Note: The formatting in the Alias column is not uniform and converting it into JSON would require significant effort.
For simplicity, the Alias column will be treated as a string, and we will only check if english_name and local_name
are substrings of Name or Alias in the WC table.

Objective:
- Identify all unique datapoints in WWD where:
  - english_name and local_name must not be equal to or a substring of any Name or Alias in WC.
  - No Name from WC should be a substring of english_name or local_name in WWD.

Capitalization should be ignored during the comparison.
*/

-- Find Unique Dishes

SELECT DISTINCT w.*
FROM WWD w
WHERE NOT EXISTS (
    SELECT 1
    FROM WC c
    WHERE
        -- Check if english_name or local_name is a substring of Name
        LOWER(c.Name) LIKE '%' || LOWER(w.english_name) || '%' OR
        LOWER(c.Name) LIKE '%' || LOWER(w.local_name) || '%' OR
        -- Check if Name is a substring of english_name or local_name
        LOWER(w.english_name) LIKE '%' || LOWER(c.Name) || '%' OR
        LOWER(w.local_name) LIKE '%' || LOWER(c.Name) || '%' OR
        -- Check if english_name or local_name is a substring of Alias
        LOWER(c.Alias) LIKE '%' || LOWER(w.english_name) || '%' OR
        LOWER(c.Alias) LIKE '%' || LOWER(w.local_name) || '%'
);

-- Find Ovelapping Dishes

SELECT DISTINCT w.*
FROM WWD w
WHERE EXISTS (
    SELECT 1
    FROM WC c
    WHERE
        -- Check if WWD's english_name or local_name overlaps with WC's Name or Alias
        LOWER(w.english_name) LIKE '%' || LOWER(c.Name) || '%'
        OR LOWER(w.local_name) LIKE '%' || LOWER(c.Name) || '%'
        OR LOWER(c.Name) LIKE '%' || LOWER(w.english_name) || '%'
        OR LOWER(c.Name) LIKE '%' || LOWER(w.local_name) || '%'
        OR LOWER(c.Alias) LIKE '%' || LOWER(w.english_name) || '%'
        OR LOWER(c.Alias) LIKE '%' || LOWER(w.local_name) || '%'
);


/*
#2 Lower bound estimate for how many data points are unique to WWD.

Objective:
We aim to estimate the lower bound for the number of unique dishes in the WWD dataset
by comparing it with the WC dataset. This is done by analyzing the number of dishes
associated with only one country in both datasets.

Identify Dishes Associated with Only One Country:
- For each country, we will consider the number of dishes in both WWD and WC datasets
  that are linked to a single country only.
- Dishes associated with multiple countries will be excluded as they may appear
  in both datasets under different countries, creating ambiguity in the estimate.
- The data for this calculation is stored in the table: Count_Dishes_With_Single_Country_WC_And_WWD.

Comparison Between Datasets:
- For each country, compare the number of dishes associated with only that country in WWD and WC.
- If the number of dishes for a country in WWD exceeds that in WC, calculate the difference.
- This difference reflects the number of dishes unique to WWD for that country.

Summing the Differences:
- Sum all differences where WWD has more dishes than WC for each country.
- This sum provides a lower bound estimate for the number of unique dishes present in WWD but not in WC.
*/

WITH SingleCountryDishesWWD AS (
    SELECT
        CASE WHEN LENGTH(countries) - LENGTH(REPLACE(countries, ',', '')) + 1 = 1 THEN countries ELSE NULL END AS country
    FROM WWD
    WHERE countries IS NOT NULL
),
CountWWD AS (
    SELECT
        country,
        COUNT(*) AS count_wwd
    FROM SingleCountryDishesWWD
    WHERE country IS NOT NULL
    GROUP BY country
),
SingleCountryDishesWC AS (
    SELECT
        json_extract(countries, '$[0]') AS country
    FROM WC
    WHERE json_array_length(countries) = 1 -- Ensures only one country in the JSON array
),
CountWC AS (
    SELECT
        country,
        COUNT(*) AS count_wc
    FROM SingleCountryDishesWC
    WHERE country IS NOT NULL
    GROUP BY country
),
CountWCAndWWD AS (
SELECT
    COALESCE(WWD.country, WC.country) AS country,
    COALESCE(count_wwd, 0) AS count_wwd,
    COALESCE(count_wc, 0) AS count_wc
FROM CountWWD WWD
FULL OUTER JOIN CountWC WC
ON WWD.country = WC.country
ORDER BY country;
),
FilteredCount AS (
SELECT count_wwd - count_wc AS difference
    FROM CountWCAndWWD
    WHERE count_wwd > count_wc
 )
 SELECT SUM(difference) AS total_difference
 FROM FilteredCount;

/*
 #3 Find how many data points we have for each country for both WC and WWD
 */

-- For WC
SELECT country, COUNT(*) AS number_of_dishes
FROM (
    SELECT json_each.value AS country
    FROM WC, json_each(WC.Countries)
)
GROUP BY country
ORDER BY number_of_dishes DESC;


-- For WWD

WITH RECURSIVE SplitCountries AS (
    -- Base case: Start with the first country in the list
    SELECT
        rowid AS dish_id,
        TRIM(SUBSTR(countries, 1, INSTR(countries || ',', ',') - 1)) AS country,
        SUBSTR(countries, INSTR(countries || ',', ',') + 1) AS remaining_countries
    FROM WWD
    WHERE countries IS NOT NULL

    UNION ALL

    -- Recursive case: Process the remaining countries
    SELECT
        dish_id,
        TRIM(SUBSTR(remaining_countries, 1, INSTR(remaining_countries || ',', ',') - 1)) AS country,
        SUBSTR(remaining_countries, INSTR(remaining_countries || ',', ',') + 1) AS remaining_countries
    FROM SplitCountries
    WHERE remaining_countries != ''
)
-- Aggregate the results
SELECT
    country,
    COUNT(DISTINCT dish_id) AS number_of_dishes
FROM SplitCountries
GROUP BY country
ORDER BY number_of_dishes DESC;


/*
 #4: Given the table with unique dishes in WWD: WWD_Unique (see first script), find the unique dish density of WWD (for every country how many unique dishes WWD has)
 */


WITH RECURSIVE SplitCountries AS (
    -- Base case: Start with the first country in the list
    SELECT
        rowid AS dish_id,
        TRIM(SUBSTR(countries, 1, INSTR(countries || ',', ',') - 1)) AS country,
        SUBSTR(countries, INSTR(countries || ',', ',') + 1) AS remaining_countries
    FROM WWD_Unique
    WHERE countries IS NOT NULL

    UNION ALL

    -- Recursive case: Process the remaining countries
    SELECT
        dish_id,
        TRIM(SUBSTR(remaining_countries, 1, INSTR(remaining_countries || ',', ',') - 1)) AS country,
        SUBSTR(remaining_countries, INSTR(remaining_countries || ',', ',') + 1) AS remaining_countries
    FROM SplitCountries
    WHERE remaining_countries != ''
)
-- Aggregate the results
SELECT
    country,
    COUNT(DISTINCT dish_id) AS number_of_dishes
FROM SplitCountries
GROUP BY country
ORDER BY number_of_dishes DESC;

/*
 #5 WWD and WC lists multiple countries per dish, for each dataset find how many dishes have X countries associated with it (0<x<=10)
 */
-- For WC
SELECT
	json_array_length(Countries) AS number_of_countries,
	COUNT(*) AS number_of_dishes
FROM
	WC
WHERE
	json_array_length(Countries) BETWEEN 1 AND 10
GROUP BY
	json_array_length(Countries)
ORDER BY
	number_of_countries;

-- For WWD
SELECT LENGTH(countries) - LENGTH(REPLACE(countries, ',', '')) + 1 AS number_of_countries,
       COUNT(*) AS number_of_dishes
FROM WWD
WHERE LENGTH(countries) - LENGTH(REPLACE(countries, ',', '')) + 1 BETWEEN 1 AND 10
GROUP BY number_of_countries
ORDER BY number_of_countries;
