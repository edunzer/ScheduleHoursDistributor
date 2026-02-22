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

## Project Structure

```
ScheduleHoursDistributor/
├── force-app/
│   └── main/
│       └── default/
│           └── classes/
│               ├── ScheduleHoursDistributor.cls          # Main Apex class
│               ├── ScheduleHoursDistributor.cls-meta.xml
│               ├── ScheduleHoursDistributorTest.cls      # Apex test class
│               └── ScheduleHoursDistributorTest.cls-meta.xml
├── scripts/
│   ├── apex/
│   │   └── hello.apex                                    # Sample Apex script
│   └── soql/
│       └── account.soql                                  # Sample SOQL query
├── sfdx-project.json                                     # SFDX project configuration
├── package.json                                          # Node.js tooling configuration
└── README.md
```

---

## Setup & Deployment

This project is a Salesforce DX (SFDX) project targeting **API version 63.0**.

### Prerequisites
- Salesforce CLI (`sf` / `sfdx`)
- A Salesforce org with the PSA (Certinia / FinancialForce) package installed
- Node.js (for linting and formatting tooling)

### Deploy to a Salesforce Org

```bash
sf project deploy start --source-dir force-app
```

### Install Node.js Dependencies

```bash
npm install
```

### Run Prettier (Code Formatter)

```bash
npm run prettier
```

### Verify Prettier Formatting

```bash
npm run prettier:verify
```

---

## How It Works

1. **Invoked from Flow**
   - The class exposes an `@InvocableMethod` that accepts a `List<ScheduleInput>`, supporting batch processing of multiple schedules in a single invocation.

2. **Input Validation**
   - Validates required fields such as schedule dates, total hours, workdays, category weeks, and percentages.
   - Ensures onsite dates (if provided) are valid and complete.
   - If `numberOfWorkDays` is 0 or less, only the existing holiday exceptions are returned (no new exceptions are generated).

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

9. **Hour Adjustment (Rounding Correction)**
   - After all exceptions are created, the total assigned hours are summed.
   - Any rounding discrepancy between the requested total and the assigned total is applied as an adjustment to the last generated exception, ensuring the total always matches exactly.

---

# Key Elements to Know

## Invocable Method

### `ScheduleHoursDistributor.generateCategoryScheduleExceptions`

This method is designed to be called from **Salesforce Flow** and serves as the single entry point for schedule exception generation. It accepts a `List<ScheduleInput>` and returns a `List<ScheduleExceptionOutputWrapper>`, allowing **batch processing** of multiple schedules in one call.

---

## Input Wrapper: `ScheduleInput`

The `ScheduleInput` class provides all parameters required for processing.

### Schedule Details
- `scheduleId`
- `startDate`
- `endDate`
- `numberOfHours`
- `numberOfWorkDays` — if `0` or less, only existing holiday exceptions are returned

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

The method returns one wrapper per input containing:

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
- A **rounding correction** is applied to the last generated exception to ensure the total assigned hours exactly match `numberOfHours`

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

---

## Public Helper Methods

The following helper methods are `public` and can be called directly in unit tests or other Apex code:

### `extractHolidayDates(List<pse__Schedule_Exception__c> existingExceptions)`
Extracts all individual dates covered by a list of schedule exceptions (used to identify holiday dates). Handles single-day and multi-day exceptions, as well as `null` entries in the list.

### `createScheduleException(Id scheduleId, Date startDate, Date endDate, Integer workDays, Decimal hoursPerDay)`
Creates and returns a single `pse__Schedule_Exception__c` record with per-day hours populated based on the `workDays` count (1 = Mon only, 5 = Mon–Fri, 7 = all days).

### `addSplitExceptions(Date segStart, Date segEnd, Decimal hoursPerDay, Integer workDays, Id scheduleId, Date inputStart, Date inputEnd, Set<Date> allSplits, List<pse__Schedule_Exception__c> allExceptions, List<pse__Schedule_Exception__c> catList)`
Iterates a date range and splits it into contiguous segments at every holiday and onsite gap date. Each uninterrupted segment is created as a separate `pse__Schedule_Exception__c` record added to both `allExceptions` and `catList`.

### `countUsableWorkdays(Date start, Date endDate, Set<Date> excludeDates)`
Counts the number of weekdays (Mon–Fri) between two dates, excluding any dates in `excludeDates` (holidays and onsite gap days).

### `isWeekday(Date d)`
Returns `true` if the given date falls on Monday through Friday.

---

## Testing

The test class `ScheduleHoursDistributorTest` provides comprehensive coverage for the main class. Tests are written as standard Salesforce Apex `@isTest` unit tests.

### Test Setup

`@testSetup` creates two `pse__Schedule__c` records and several `pse__Schedule_Exception__c` holiday records that are shared across tests:

- **Schedule 1** — Jan 1 to Jul 1, 2025 (200 hours, 7-day work week)
- **Schedule 2** — Jan 1 to Jul 1, 2026 (100 hours, 5-day work week)
- **Holiday exceptions** — Jan 8 2025 (single-day), Mar 10–12 2025 (multi-day), Mar 13 2025 (single-day)

### Test Methods

| Test Method | What It Validates |
|---|---|
| `testGenerateScheduleExceptions` | Happy path — valid input with onsite generates exceptions without errors |
| `testGenerateScheduleExceptionsWithNullScheduleId` | Null `scheduleId` returns a specific validation error |
| `testStartDateAfterEndDateValidation` | `startDate > endDate` returns validation error |
| `testOnsiteStartAfterEndDateValidation` | `onsiteStartDate > onsiteEndDate` returns validation error |
| `testExistingMultiDayExceptionExcludesHolidayDates` | No generated exception overlaps a multi-day holiday range |
| `testOnsiteGapWeekIsSevenDaysZeroHours` | Onsite gap week is exactly 7 days with all-zero hours |
| `testPercentSumLessAndGreaterThan100` | Percentages summing to < 100 or > 100 are normalized correctly |
| `testMathWithoutExistingExceptions_TotalHoursMatch` | Total distributed hours exactly match requested hours |
| `testMathWithExistingHolidayExcludesDate_TotalHoursMatch` | Holiday dates are excluded and total hours still match |
| `testExtractHolidayDates_NullAndRanges` | `extractHolidayDates` handles null entries, single-day, and multi-day exceptions |
| `testAddSplitExceptions_SplittingBehavior` | `addSplitExceptions` correctly splits segments at split dates |
| `testCountUsableWorkdays_VariousRanges` | `countUsableWorkdays` counts correctly with weekends and excluded dates |
| `testAllCategoriesInvalid_NoCrash` | Zero-week categories produce no exceptions without throwing an error |
| `testGenerateScheduleExceptions_MultipleValidInputs` | Batch processing of two valid inputs returns two wrappers |
| `testGenerateScheduleExceptions_MixedValidAndInvalidInputs` | Batch processing of valid + invalid input returns one success and one error |
| `testGenerateScheduleExceptions_TwoValidInputs_NoErrors` | Two valid inputs both return wrappers with no errors |

