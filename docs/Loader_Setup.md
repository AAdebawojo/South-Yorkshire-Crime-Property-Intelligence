# CrimeData – setup and run guide

Loads South Yorkshire data from the data.police.uk API into PostgreSQL. You view and query it in DBeaver.

Files:
- `load_crime_data.py`: the loader
- `schema.sql`: the tables (the loader runs this for you)
- `requirements.txt`: the Python packages

---

## 1. Install PostgreSQL (skip this if you already have it)

DBeaver is only a client, so the database itself runs in PostgreSQL.

1. Download the installer from https://www.postgresql.org/download/ (version 16 or 17).
2. During setup:
   - Set a password for the **postgres** superuser and **write it down**.
   - Keep the default port, **5432**.
   - You can skip Stack Builder.
3. PostgreSQL runs as a background service from then on.

## 2. Connect DBeaver to PostgreSQL

1. In DBeaver, go to **Database → New Database Connection** (or click the plug icon with a +).
2. Choose **PostgreSQL** and click **Next**.
3. On the **Main** tab:
   - Host: `localhost`  Port: `5432`
   - Database: `postgres` (CrimeData doesn't exist yet, so connect to the default database first)
   - Authentication: *Database Native*, Username: `postgres`, Password: your password, and tick **Save password**
4. On the same tab, tick **Show all databases**. Without it, DBeaver won't list CrimeData once it has been created.
5. Click **Test Connection**. If DBeaver asks to download the PostgreSQL driver, click **Download**.
6. Click **Finish**.

## 3. Install the Python packages

Open a terminal (Command Prompt or PowerShell on Windows) in the folder that holds the files:

```
pip install -r requirements.txt
```

(Use `py -m pip install -r requirements.txt` on Windows if `pip` isn't recognised.)

## 4. Create the database and tables

```
python load_crime_data.py --schema-only
```

The script asks for your postgres password. It then creates the **CrimeData** database and the **police** schema with all the tables.

To check it in DBeaver, right-click the connection and choose **Refresh**. Then expand **Databases → CrimeData → Schemas → police → Tables**.

> To avoid typing the password each time, set it as an environment variable first.
> PowerShell: `$env:PGPASSWORD="yourpassword"`, Command Prompt: `set PGPASSWORD=yourpassword`

If your PostgreSQL user, host or port differ from the defaults, add
`--user myuser --host myhost --port 5433`.

## 5. Do a quick test load (about 1 minute)

```
python load_crime_data.py --test
```

This loads the latest month for 3 neighbourhoods. In DBeaver, open an SQL editor on CrimeData (**SQL Editor → New SQL script**, or Ctrl+]) and run:

```sql
SELECT * FROM police.v_crimes LIMIT 100;
```

## 6. Run the full load

```
python load_crime_data.py
```

- It fetches every month the API holds (about 3 years) for every South Yorkshire neighbourhood, plus outcomes.
- **Expect it to take 1–3 hours.** The API is rate limited and the polygon queries are slow.
- You can stop it with Ctrl+C at any time. Run the same command again and it carries on from where it stopped. If anything failed, running it again retries only those pieces.
- Useful options:
  - `--start 2025-01 --end 2025-12` loads only those months.
  - `--skip-outcomes` skips the outcomes table and roughly halves the run time.
  - `--refresh` re-fetches months already loaded. Use it when the police update their figures.
  - `--workers 6` sends more requests in parallel. Don't go much higher, or the API will start rejecting requests.

Each month the police publish new data. Running the script again picks up the new month automatically.

---

## What's in the database (schema `police`)

| Table | Contents | API source |
|---|---|---|
| `forces` | All UK forces, plus South Yorkshire's details | `/forces`, `/forces/{id}` |
| `available_months` | Months the API holds | `/crimes-street-dates` |
| `crime_categories` | Category code → name | `/crime-categories` |
| `outcome_categories` | Outcome code → name | from outcomes |
| `neighbourhoods` | South Yorkshire neighbourhoods, contact details, centre, boundary as WKT | `/{force}/neighbourhoods`, `/{force}/{id}` |
| `neighbourhood_boundary_points` | Boundary vertices, one row per point | `/{force}/{id}/boundary` |
| `locations` | Anonymised map points ("On or near …"), each tagged with its neighbourhood | from crimes |
| `crimes` | One row per crime: category, month, location, latest outcome | `/crimes-street/all-crime`, `/crimes-no-location` |
| `outcomes` | Full outcome history (join to `crimes` on `persistent_id`) | `/outcomes-at-location` |
| `load_log`, `load_runs` | What has been loaded and when | — |

Views:
- `v_crimes`: crimes joined to category name, street and neighbourhood
- `v_monthly_counts`: crime counts by month, neighbourhood and category

To see the table relationships in DBeaver, open **police → Tables** and click the **ER Diagram** tab.

### Example queries

```sql
-- Crimes per month, all South Yorkshire
SELECT crime_month, COUNT(*) FROM police.crimes GROUP BY 1 ORDER BY 1;

-- Top 10 neighbourhoods for burglary in the last 12 months
SELECT neighbourhood_name, COUNT(*) AS burglaries
FROM police.v_crimes
WHERE category_code = 'burglary'
  AND crime_month >= (SELECT MAX(crime_month) FROM police.crimes) - INTERVAL '11 months'
GROUP BY 1 ORDER BY 2 DESC LIMIT 10;

-- Outcome history for crimes
SELECT c.crime_month, c.category_code, o.outcome_month, oc.outcome_name
FROM police.crimes c
JOIN police.outcomes o            ON o.persistent_id = c.persistent_id
JOIN police.outcome_categories oc ON oc.outcome_code = o.outcome_code
ORDER BY c.crime_id, o.outcome_month;
```

## Notes on the data

- Locations are anonymised by the police and snapped to a nearby point, so they are approximate.
- Anti-social behaviour records have no `persistent_id` and no outcomes.
- `location_type = 'BTP'` rows are British Transport Police crimes at railway locations inside South Yorkshire.
- A crime within about 15 m of the force boundary could in rare cases belong to a neighbouring force. Crimes further outside the boundary are discarded.
- Outcomes are only available for crimes that have a location.

## Troubleshooting

| Problem | Fix |
|---|---|
| `password authentication failed` | Wrong password or user. Check the details you use in DBeaver. |
| `could not connect to server` | The PostgreSQL service isn't running (Windows: Services → postgresql-x64-NN → Start), or the port is wrong. |
| `permission denied to create database` | Use a user with CREATEDB rights (postgres has them), or create the database in DBeaver yourself: right-click **Databases → Create New Database**, name it `CrimeData`. Then rerun. |
| CrimeData isn't visible in DBeaver | Edit Connection → Main tab → tick **Show all databases**, then Refresh. |
| Lots of `FAILED` lines | The API was busy. Wait a few minutes and run again. Only the failed pieces are retried. |
