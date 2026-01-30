# ScheduleHoursDistributor

## What It Is

`ScheduleHoursDistributor` is a Salesforce Apex class that generates PSA (Certinia / FinancialForce) Schedule Exception records by distributing a total number of planned hours across multiple project phases (Cat1, Cat2, Cat3, and optionally Post) using a bell-curve–style schedule.

Its primary purpose is to create a realistic workload pattern where scheduled hours start low, gradually increase to a peak, and then taper off again, rather than being evenly or manually assigned.

The class is designed to be invoked from Salesforce Flow and automatically handles:
- Bell-curve–based hour allocation by category
- Holiday exclusion
- Workday-based calculations
- Optional onsite periods with gap handling

The overall goal is to replace manual schedule exception entry with consistent, rule-driven automation that produces more natural, balanced schedules.

---

## How It Works

1. **Invoked from Flow**
   - The class exposes an `@InvocableMethod` that accepts a single `ScheduleInput`.

2. **Input Validation**
   - Validates required fields such as schedule dates, total hours, workdays, category weeks, and percentages.
   - Ensures onsite dates (if provided) are valid and complete.

3. **Holiday Processing**
   - Holiday dates are extracted from existing schedule exceptions.
   - These dates are excluded from hour calculations and exception creation.

4. **Onsite Logic (Optional)**
   - If an onsite period is detected (< 30 days and within the schedule range):
     - A full Monday–Sunday onsite gap week is reserved.
     - The gap week receives a zero-hour schedule exception.
     - All category allocations exclude the onsite gap.
     - The Post category is created only when onsite is valid.

5. **Category Range Calculation**
   - Category durations are converted from weeks to days (`weeks × 7`, decimals truncated).
   - Categories are calculated backward from the schedule end date.
   - Each category is trimmed to the overall schedule window.
   - Categories that do not overlap the schedule are ignored.

6. **Percentage Redistribution**
   - Only valid categories are included.
   - Percentages are normalized so the total always equals 100%.
   - Any unused or excess percentage is redistributed evenly.

7. **Hour Distribution**
   - Usable weekdays (Mon–Fri) are counted per category.
   - Holidays and onsite gap days are excluded.
   - Daily hours are calculated based on category percentage and usable days.

8. **Schedule Exception Creation**
   - Category ranges are split at holidays and onsite gap dates.
   - Each uninterrupted segment becomes its own `pse__Schedule_Exception__c` record.
   - All generated exceptions are returned to Flow.

---

# Key Elements to Know

## Invocable Method

### `ScheduleHoursDistributor.generateCategoryScheduleExceptions`

This method is designed to be called from **Salesforce Flow** and serves as the single entry point for schedule exception generation.

---

## Input Wrapper: `ScheduleInput`

The `ScheduleInput` class provides all parameters required for processing.

### Schedule Details
- `scheduleId`
- `startDate`
- `endDate`
- `numberOfHours`
- `numberOfWorkDays`

### Category Configuration
- `cat1Weeks`, `cat2Weeks`, `cat3Weeks`, `postWeeks`
- `cat1Percentage`, `cat2Percentage`, `cat3Percentage`, `postPercentage`

### Optional Onsite Period
- `onsiteStartDate`
- `onsiteEndDate`

### Existing Exceptions
- `existingExceptions`  
  Used to identify holiday dates that must be excluded from calculations.

---

## Output Wrapper: `ScheduleExceptionOutputWrapper`

The method returns a single wrapper containing:

- `scheduleExceptions`  
  A list of newly generated `pse__Schedule_Exception__c` records.

- `errorMessage`  
  A descriptive message populated when validation or execution fails.  
  If successful, this value is `null`.

---

## Category Behavior

### Supported Categories
- Cat 1
- Cat 2
- Cat 3
- Post (created only when a valid onsite period exists)

### Calculation Rules
- Category durations are calculated in **days**, not weeks:
  - `weeks × 7` (decimals truncated)
- Categories are calculated **backward** from the schedule end date
- Categories that do not overlap the schedule range are ignored

---

## Hour Allocation Rules

- Hours are assigned only to **weekdays (Monday–Friday)**
- Holidays and onsite gap days are **always excluded**
- Category percentages are **normalized** so valid categories total **100%**
- Daily hours are calculated using **usable workdays only**

---

## Onsite Handling

Onsite is considered valid only if:

- Duration is **less than 30 days**
- Fully contained within the schedule range

### Onsite Gap Week
- A full **Monday–Sunday onsite gap week** is reserved
- The gap week generates a **zero-hour schedule exception**
- All category allocations **exclude onsite gap days**
- The **Post** category begins **after the onsite gap week ends**

