-- Auto-assign cuisines for all existing restaurants in Supabase
-- Run this in your Supabase SQL Editor

-- First, ensure the column exists
ALTER TABLE saved_places ADD COLUMN IF NOT EXISTS user_cuisine text;

-- Update restaurants that don't have a cuisine assigned
UPDATE saved_places
SET user_cuisine = CASE
    -- Pakistani
    WHEN LOWER(name) LIKE '%pakistani%' OR LOWER(name) LIKE '%biryani%' OR LOWER(name) LIKE '%karahi%' OR LOWER(name) LIKE '%nihari%' THEN 'Pakistani'
    
    -- Middle Eastern
    WHEN LOWER(name) LIKE '%shawarma%' OR LOWER(name) LIKE '%kebab%' OR LOWER(name) LIKE '%falafel%' 
        OR LOWER(name) LIKE '%middle eastern%' OR LOWER(name) LIKE '%lebanese%' OR LOWER(name) LIKE '%persian%' 
        OR LOWER(name) LIKE '%halal%' OR LOWER(name) LIKE '%arabian%' THEN 'Middle Eastern'
    
    -- Indian
    WHEN LOWER(name) LIKE '%indian%' OR LOWER(name) LIKE '%tandoori%' OR LOWER(name) LIKE '%curry house%' 
        OR LOWER(name) LIKE '%masala%' OR LOWER(name) LIKE '%tikka%' THEN 'Indian'
    
    -- Italian
    WHEN LOWER(name) LIKE '%italian%' OR LOWER(name) LIKE '%pizzeria%' OR LOWER(name) LIKE '%trattoria%' 
        OR LOWER(name) LIKE '%ristorante%' OR LOWER(name) LIKE '%pasta%' THEN 'Italian'
    
    -- Chinese
    WHEN LOWER(name) LIKE '%chinese%' OR LOWER(name) LIKE '%szechuan%' OR LOWER(name) LIKE '%cantonese%' 
        OR LOWER(name) LIKE '%dim sum%' OR LOWER(name) LIKE '%wok%' THEN 'Chinese'
    
    -- Japanese
    WHEN LOWER(name) LIKE '%japanese%' OR LOWER(name) LIKE '%sushi%' OR LOWER(name) LIKE '%ramen%' 
        OR LOWER(name) LIKE '%izakaya%' OR LOWER(name) LIKE '%tempura%' OR LOWER(name) LIKE '%teriyaki%' THEN 'Japanese'
    
    -- Korean
    WHEN LOWER(name) LIKE '%korean%' OR LOWER(name) LIKE '%bulgogi%' OR LOWER(name) LIKE '%bibimbap%' THEN 'Korean'
    
    -- Thai
    WHEN LOWER(name) LIKE '%thai%' OR LOWER(name) LIKE '%pad thai%' THEN 'Thai'
    
    -- Vietnamese
    WHEN LOWER(name) LIKE '%vietnamese%' OR LOWER(name) LIKE '%pho%' OR LOWER(name) LIKE '%banh mi%' THEN 'Vietnamese'
    
    -- Mexican
    WHEN LOWER(name) LIKE '%mexican%' OR LOWER(name) LIKE '%taco%' OR LOWER(name) LIKE '%burrito%' 
        OR LOWER(name) LIKE '%taqueria%' OR LOWER(name) LIKE '%cantina%' THEN 'Mexican'
    
    -- French
    WHEN LOWER(name) LIKE '%french%' OR LOWER(name) LIKE '%bistro%' OR LOWER(name) LIKE '%brasserie%' 
        OR LOWER(name) LIKE '%patisserie%' THEN 'French'
    
    -- Greek
    WHEN LOWER(name) LIKE '%greek%' OR LOWER(name) LIKE '%gyro%' OR LOWER(name) LIKE '%souvlaki%' THEN 'Greek'
    
    -- Turkish
    WHEN LOWER(name) LIKE '%turkish%' OR LOWER(name) LIKE '%doner%' THEN 'Turkish'
    
    -- Mediterranean
    WHEN LOWER(name) LIKE '%mediterranean%' THEN 'Mediterranean'
    
    -- Jamaican
    WHEN LOWER(name) LIKE '%jamaican%' OR LOWER(name) LIKE '%jerk%' THEN 'Jamaican'
    
    -- Caribbean
    WHEN LOWER(name) LIKE '%caribbean%' THEN 'Caribbean'
    
    -- Seafood
    WHEN LOWER(name) LIKE '%seafood%' OR LOWER(name) LIKE '%lobster%' OR LOWER(name) LIKE '%oyster%' 
        OR LOWER(name) LIKE '%fish market%' OR LOWER(name) LIKE '%crab%' THEN 'Seafood'
    
    -- Pizza
    WHEN LOWER(name) LIKE '%pizza%' THEN 'Pizza'
    
    -- Burger
    WHEN LOWER(name) LIKE '%burger%' THEN 'Burger'
    
    -- BBQ
    WHEN LOWER(name) LIKE '%bbq%' OR LOWER(name) LIKE '%barbecue%' OR LOWER(name) LIKE '%smokehouse%' 
        OR LOWER(name) LIKE '%grill house%' THEN 'BBQ'
    
    -- American
    WHEN LOWER(name) LIKE '%american%' OR LOWER(name) LIKE '%diner%' THEN 'American'
    
    -- Cafe
    WHEN LOWER(name) LIKE '%coffee%' OR LOWER(name) LIKE '%cafe%' OR LOWER(name) LIKE '%café%' 
        OR LOWER(name) LIKE '%starbucks%' OR LOWER(name) LIKE '%tim hortons%' THEN 'Cafe'
    
    -- Vegetarian
    WHEN LOWER(name) LIKE '%vegan%' OR LOWER(name) LIKE '%vegetarian%' OR LOWER(name) LIKE '%plant%' THEN 'Vegetarian'
    
    ELSE user_cuisine -- Keep existing value if no match
END
WHERE user_cuisine IS NULL 
  AND LOWER(category) LIKE '%restaurant%';

-- Show how many were updated
SELECT 
    user_cuisine, 
    COUNT(*) as count 
FROM saved_places 
WHERE user_cuisine IS NOT NULL 
GROUP BY user_cuisine 
ORDER BY count DESC;
