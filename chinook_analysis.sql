-- =============================================================================
-- CHINOOK DATABASE ANALYSIS
-- SQL queries answering business questions about a digital music store
-- Dataset: Chinook (BigQuery) — `da-nfactorial.chinook.*`
-- =============================================================================


-- =============================================================================
-- PART 1: CUSTOMER & SALES OVERVIEW
-- =============================================================================

-- Q1: Which countries have the most invoices?
SELECT
  BillingCountry,
  COUNT(InvoiceID) AS Invoices
FROM `da-nfactorial.chinook.invoice`
GROUP BY BillingCountry
ORDER BY Invoices DESC;


-- Q2: Which city generated the highest total invoice revenue?
SELECT
  BillingCity,
  SUM(Total) AS InvoicesSum
FROM `da-nfactorial.chinook.invoice`
GROUP BY BillingCity
ORDER BY InvoicesSum DESC
LIMIT 1;

-- Alternative (CTE, no LIMIT — handles ties)
WITH CityTotals AS (
  SELECT
    BillingCity,
    SUM(Total) AS InvoicesSum
  FROM `da-nfactorial.chinook.invoice`
  GROUP BY BillingCity
)
SELECT *
FROM CityTotals
WHERE InvoicesSum = (SELECT MAX(InvoicesSum) FROM CityTotals);


-- Q3: Who is the best customer (highest total spend)?
SELECT
  CONCAT(c.FirstName, ' ', c.LastName) AS BestCustomer,
  SUM(i.Total) AS TotalInvoice
FROM `da-nfactorial.chinook.invoice` i
LEFT JOIN `da-nfactorial.chinook.customer` c
  ON i.CustomerId = c.CustomerId
GROUP BY BestCustomer
ORDER BY TotalInvoice DESC
LIMIT 1;

-- Alternative (CTE, no LIMIT — handles ties)
WITH CustomerTotals AS (
  SELECT
    CONCAT(c.FirstName, ' ', c.LastName) AS Name,
    SUM(i.Total) AS TotalInvoice
  FROM `da-nfactorial.chinook.invoice` i
  LEFT JOIN `da-nfactorial.chinook.customer` c
    ON i.CustomerId = c.CustomerId
  GROUP BY Name
)
SELECT *
FROM CustomerTotals
WHERE TotalInvoice = (SELECT MAX(TotalInvoice) FROM CustomerTotals);


-- Q4: Which tracks are longer than the average track length?
SELECT
  Name,
  Milliseconds
FROM `da-nfactorial.chinook.track`
WHERE Milliseconds > (SELECT AVG(Milliseconds) FROM `da-nfactorial.chinook.track`)
ORDER BY Milliseconds DESC;


-- =============================================================================
-- PART 2: GENRE, ARTIST & CUSTOMER DEEP DIVE
-- =============================================================================

-- Q5: Who listens to rock music? (email, name, genre)
SELECT
  c.Email,
  CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
  g.Name
FROM `da-nfactorial.chinook.customer` c
LEFT JOIN `da-nfactorial.chinook.Genre2` gg
  ON c.CustomerId = gg.customerid
LEFT JOIN `da-nfactorial.chinook.genre` g
  ON g.GenreId = gg.GenreId
WHERE g.Name LIKE '%Rock%'
ORDER BY c.Email;
-- Alternative: WHERE REGEXP_CONTAINS(g.Name, r'Rock')


-- Q6: Top 10 artists by number of rock tracks written
SELECT
  COALESCE(t.Composer, 'Unknown') AS Artist,
  COUNT(t.TrackId) AS TrackCount
FROM `da-nfactorial.chinook.track` t
LEFT JOIN `da-nfactorial.chinook.genre` g
  ON t.GenreId = g.GenreId
WHERE g.Name LIKE '%Rock%'
GROUP BY Artist
ORDER BY TrackCount DESC
LIMIT 10;


-- Q7: Top-earning artist, and the customer who spent the most on that artist
WITH CTE_ArtistTotalSales AS (
  SELECT
    t.Composer AS Artist,
    ROUND(SUM(il.UnitPrice * il.Quantity), 2) AS TotalSales
  FROM `da-nfactorial.chinook.invoiceline` il
  LEFT JOIN `da-nfactorial.chinook.track` t
    ON il.TrackId = t.TrackId
  WHERE t.Composer IS NOT NULL
  GROUP BY t.Composer
  ORDER BY TotalSales DESC
  LIMIT 1
),
CTE_CustomerTotalSpent AS (
  SELECT
    COALESCE(CONCAT(c.FirstName, ' ', c.LastName), 'Unknown') AS CustomerName,
    t.Composer AS Artist,
    ROUND(SUM(il.UnitPrice * il.Quantity), 2) AS TotalSpent
  FROM `da-nfactorial.chinook.invoiceline` il
  LEFT JOIN `da-nfactorial.chinook.track` t
    ON il.TrackId = t.TrackId
  LEFT JOIN `da-nfactorial.chinook.invoice` i
    ON i.InvoiceId = il.InvoiceId
  LEFT JOIN `da-nfactorial.chinook.customer` c
    ON c.CustomerId = i.CustomerId
  WHERE t.Composer IS NOT NULL
  GROUP BY CustomerName, Artist
)
SELECT
  cs.CustomerName,
  cs.TotalSpent,
  a.Artist
FROM CTE_CustomerTotalSpent cs
JOIN CTE_ArtistTotalSales a
  ON cs.Artist = a.Artist
ORDER BY cs.TotalSpent DESC
LIMIT 1;


-- Q8: Most popular genre per country (by number of purchases)
WITH CountrySales AS (
  SELECT
    COALESCE(g.Name, 'Unknown') AS GenreName,
    c.Country,
    COUNT(il.InvoiceLineId) AS SalesQuantity
  FROM `da-nfactorial.chinook.customer` c
  LEFT JOIN `da-nfactorial.chinook.invoice` i
    ON i.CustomerId = c.CustomerId
  LEFT JOIN `da-nfactorial.chinook.invoiceline` il
    ON il.InvoiceId = i.InvoiceId
  LEFT JOIN `da-nfactorial.chinook.track` t
    ON t.TrackId = il.TrackId
  LEFT JOIN `da-nfactorial.chinook.genre` g
    ON g.GenreId = t.GenreId
  GROUP BY GenreName, c.Country
),
MaxPerCountry AS (
  SELECT
    Country,
    MAX(SalesQuantity) AS MaxSales
  FROM CountrySales
  GROUP BY Country
)
SELECT
  cs.Country,
  cs.GenreName,
  cs.SalesQuantity
FROM CountrySales cs
JOIN MaxPerCountry m
  ON cs.Country = m.Country
  AND cs.SalesQuantity = m.MaxSales
ORDER BY cs.Country;


-- Q9: Top-spending customer per country
WITH CountrySales AS (
  SELECT
    CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
    c.Country,
    ROUND(SUM(i.Total), 2) AS SalesAmount
  FROM `da-nfactorial.chinook.customer` c
  LEFT JOIN `da-nfactorial.chinook.invoice` i
    ON i.CustomerId = c.CustomerId
  GROUP BY CustomerName, c.Country
),
MaxPerCountry AS (
  SELECT
    Country,
    MAX(SalesAmount) AS MaxSales
  FROM CountrySales
  GROUP BY Country
)
SELECT
  cs.Country,
  cs.CustomerName,
  cs.SalesAmount
FROM CountrySales cs
JOIN MaxPerCountry m
  ON cs.Country = m.Country
  AND cs.SalesAmount = m.MaxSales
ORDER BY cs.Country;


-- =============================================================================
-- PART 3: CUSTOM BUSINESS ANALYSIS
-- =============================================================================

-- Q10: Which sales support agents generated the most revenue?
SELECT
  CONCAT(e.FirstName, ' ', e.LastName) AS EmployeeName,
  SUM(i.Total) AS TotalSales
FROM `da-nfactorial.chinook.employee` e
LEFT JOIN `da-nfactorial.chinook.customer` c
  ON e.EmployeeId = c.SupportRepId
LEFT JOIN `da-nfactorial.chinook.invoice` i
  ON i.CustomerId = c.CustomerId
WHERE e.Title = 'Sales Support Agent'
GROUP BY EmployeeName
ORDER BY TotalSales DESC;


-- Q11: Which media format (MP3, AAC, etc.) sells the most?
SELECT
  m.Name,
  COUNT(il.InvoiceLineId) AS SalesQty
FROM `da-nfactorial.chinook.mediatype` m
LEFT JOIN `da-nfactorial.chinook.track` t
  ON m.MediaTypeId = t.MediaTypeId
LEFT JOIN `da-nfactorial.chinook.invoiceline` il
  ON t.TrackId = il.TrackId
GROUP BY m.Name
ORDER BY SalesQty DESC;


-- Q12: Which country generates the most revenue in each month?
WITH CountrySales AS (
  SELECT
    FORMAT_DATE('%B', i.InvoiceDate) AS Month,
    EXTRACT(MONTH FROM i.InvoiceDate) AS MonthNum,
    c.Country,
    ROUND(SUM(i.Total), 2) AS TotalSales
  FROM `da-nfactorial.chinook.invoice` i
  LEFT JOIN `da-nfactorial.chinook.customer` c
    ON i.CustomerId = c.CustomerId
  GROUP BY Month, MonthNum, c.Country
),
MaxPerMonth AS (
  SELECT
    Month,
    MAX(TotalSales) AS MaxSales
  FROM CountrySales
  GROUP BY Month
)
SELECT
  cs.MonthNum,
  cs.Month,
  cs.Country,
  cs.TotalSales
FROM CountrySales cs
JOIN MaxPerMonth mm
  ON mm.Month = cs.Month
  AND mm.MaxSales = cs.TotalSales
ORDER BY cs.MonthNum;


-- Q13: Which playlists contain the most tracks?
SELECT
  p.Name,
  COUNT(pt.TrackId) AS TrackQty
FROM `da-nfactorial.chinook.playlist` p
LEFT JOIN `da-nfactorial.chinook.playlisttrack` pt
  ON p.PlaylistId = pt.PlaylistId
GROUP BY p.Name
ORDER BY TrackQty DESC;

-- Variant: exclude empty playlists
SELECT
  p.Name,
  COUNT(pt.TrackId) AS TrackQty
FROM `da-nfactorial.chinook.playlist` p
LEFT JOIN `da-nfactorial.chinook.playlisttrack` pt
  ON p.PlaylistId = pt.PlaylistId
GROUP BY p.Name
HAVING COUNT(pt.TrackId) > 0
ORDER BY TrackQty DESC;
