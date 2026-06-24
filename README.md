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
   - The class exposes an `@InvocableMethod` that accepts a `List<ScheduleInput>`, supporting batch processing of multiple schedules in a single invocation.

2. **Input Validation**
   - Validates required fields such as schedule dates, total hours, workdays, category weeks, and percentages.
   - `numberOfHours` must be greater than zero — a zero or negative value returns an explicit validation error.
   - All week values (`cat1Weeks`, `cat2Weeks`, `cat3Weeks`, `postWeeks`) must be zero or positive — negative values return an explicit validation error.
   - All percentage values (`cat1Percentage`, `cat2Percentage`, `cat3Percentage`, `postPercentage`) must be zero or positive — negative values return an explicit validation error.
   - `numberOfWorkDays` is bounded to the supported range `1..7` before allocation and exception-field population.
   - Ensures onsite dates (if provided) are valid and complete.

3. **Holiday Processing**
   - Holiday dates are extracted from existing schedule exceptions.
   - These dates are excluded from hour calculations and exception creation.

4. **Onsite Logic (Optional)**
   - If an onsite period is detected (< 30 days and within the schedule range):
   - A Monday–Sunday onsite gap week is calculated.
   - Weekday normalization is runtime-context aware so Monday is always treated as day 1 regardless of locale ordering.
   - The generated onsite gap exception is clamped to the input schedule range.
     - The gap week receives a zero-hour schedule exception.
     - All category allocations exclude the onsite gap.
     - The Post category is created only when onsite is valid.

5. **Category Range Calculation**
   - Category durations are converted from weeks to days (`weeks × 7`, decimals truncated).
   - Categories are calculated backward from the schedule end date.
   - The Post category is constrained by `postWeeks` (`postWeeks × 7` days) and capped to the schedule end date.
   - Each category is trimmed to the overall schedule window.
   - Categories that do not overlap the schedule are ignored.

6. **Percentage Redistribution**
   - Only valid categories are included.
   - Percentages are normalized so the total always equals 100%.
   - Any unused or excess percentage is redistributed evenly.

7. **Hour Distribution**
   - Usable days are counted per category using `numberOfWorkDays`.
   - Workday patterns are: `1 = Mon`, `5 = Mon–Fri`, `6 = Mon–Sat`, `7 = Mon–Sun`.
   - Holidays and onsite gap days are excluded.
   - Daily hours are calculated using a capacity-aware allocation model.
   - A hard cap of `24` hours/day is enforced.
   - Overflow is redistributed across categories with remaining capacity (up to 4 passes).

8. **Schedule Exception Creation**
   - Category ranges are split at holidays and onsite gap dates.
   - Each uninterrupted segment becomes its own `pse__Schedule_Exception__c` record.
   - All generated exceptions are returned to Flow.

9. **Remainder Handling**
   - If requested hours exceed total schedulable capacity, the method does **not** throw an error.
   - The method schedules as many hours as possible and leaves the remainder unscheduled.
   - This allows planned hours and scheduled hours to differ when users over-assign hours.

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
- `numberOfWorkDays` — number of working days per week. Values are bounded to `1..7` (e.g., `5` for Mon–Fri, `7` for all days).

### Category Configuration
- `cat1Weeks`, `cat2Weeks`, `cat3Weeks`, `postWeeks`
- `cat1Percentage`, `cat2Percentage`, `cat3Percentage`, `postPercentage`

### Optional Onsite Period
- `onsiteStartDate`
- `onsiteEndDate`

### Existing Exceptions
- `existingExceptions`  
  Used to identify holiday dates that must be excluded from calculations. Existing exceptions are **never** included in the output — only new exceptions generated by the method are returned.

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

- Hours are assigned to the first `numberOfWorkDays` days of each week (for example: `5 = Mon–Fri`, `7 = Mon–Sun`)
- Usable-day counting uses the same `numberOfWorkDays` pattern as hour assignment
- Out-of-range `numberOfWorkDays` inputs are consistently bounded to `1..7` across both day counting and schedule-exception day fields
- Holidays and onsite gap days are **always excluded**
- Category percentages are **normalized** so valid categories total **100%**
- Capacity is calculated per category as `usableDays × 24`
- Initial assignment is percentage-based, then capped by category capacity
- Overflow is rolled into other categories with available capacity
- Redistribution is limited to a maximum of **4 passes**
- Per-day assigned hours are capped at **24**
- If capacity is exhausted, remaining requested hours are intentionally left unscheduled (no error)

---

## Onsite Handling

Onsite is considered valid only if:

- Duration is **less than 30 days**
- Fully contained within the schedule range

### Onsite Gap Week
- A **Monday–Sunday onsite gap week** is calculated
- The generated onsite gap exception is **clamped to the input schedule window** (`startDate` to `endDate`)
- The gap week generates a **zero-hour schedule exception**
- All category allocations **exclude onsite gap days**
- The **Post** category begins **after the onsite gap week ends** and lasts up to `postWeeks × 7` days, capped by `endDate`

---

## Public Helper Methods

The following helper methods are `public` and can be called directly in unit tests or other Apex code:

### `extractHolidayDates(List<pse__Schedule_Exception__c> existingExceptions)`
Extracts all individual dates covered by a list of schedule exceptions (used to identify holiday dates). Handles single-day and multi-day exceptions, as well as `null` entries in the list.

### `createScheduleException(Id scheduleId, Date startDate, Date endDate, Integer workDays, Decimal hoursPerDay)`
Creates and returns a single `pse__Schedule_Exception__c` record with per-day hours populated based on the `workDays` count. `workDays` is bounded to `1..7` (1 = Mon only, 5 = Mon–Fri, 7 = all days).

### `addSplitExceptions(Date segStart, Date segEnd, Decimal hoursPerDay, Integer workDays, Id scheduleId, Date inputStart, Date inputEnd, Set<Date> allSplits, List<pse__Schedule_Exception__c> allExceptions, List<pse__Schedule_Exception__c> catList)`
Iterates a date range and splits it into contiguous segments at every holiday and onsite gap date. Each uninterrupted segment is created as a separate `pse__Schedule_Exception__c` record added to both `allExceptions` and `catList`.

### `countUsableWorkdays(Date start, Date endDate, Set<Date> excludeDates, Integer numberOfWorkDays)`
Counts usable days between two dates based on `numberOfWorkDays` (1-7), excluding any dates in `excludeDates` (holidays and onsite gap days).

### `countUsableWorkdays(Date start, Date endDate, Set<Date> excludeDates)`
Backward-compatible overload that defaults to `5` (Mon–Fri).

### `isScheduledWorkday(Date d, Integer numberOfWorkDays)`
Returns `true` when a date falls within the configured weekly work pattern (`1 = Mon` through `7 = Mon–Sun`).

### `isWeekday(Date d)`
Returns `true` if the given date falls on Monday through Friday.

### `getNormalizedDayOfWeek(Date d)`
Returns a normalized weekday index where **Monday = 1** and **Sunday = 7**. The method adapts to runtime locale/context ordering so downstream scheduling logic remains stable.

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
| `testNegativeNumberOfHours_ReturnsError` | `numberOfHours <= 0` returns an explicit validation error instead of silently under-allocating |
| `testNegativeCatWeeks_ReturnsError` | Negative week values return an explicit validation error |
| `testNegativePercentages_ReturnsError` | Negative percentage values return an explicit validation error |
| `testExistingMultiDayExceptionExcludesHolidayDates` | No generated exception overlaps a multi-day holiday range |
| `testOnsiteGapWeekIsSevenDaysZeroHours` | Onsite gap week is exactly 7 days with all-zero hours |
| `testGetNormalizedDayOfWeek_MondayIsOne` | Runtime normalization always maps Monday to 1 and Sunday to 7 |
| `testNumberOfWorkDaysOutOfRange_IsConsistentEverywhere` | Out-of-range `numberOfWorkDays` values are bounded consistently for usable-day counting and exception day-field population |
| `testPercentSumLessAndGreaterThan100` | Percentages summing to < 100 or > 100 are normalized correctly |
| `testMathWithoutExistingExceptions_TotalHoursMatch` | Scheduled hours do not exceed requested hours |
| `testMathWithExistingHolidayExcludesDate_TotalHoursMatch` | Holiday dates are excluded and scheduled hours do not exceed requested hours |
| `testExtractHolidayDates_NullAndRanges` | `extractHolidayDates` handles null entries, single-day, and multi-day exceptions |
| `testAddSplitExceptions_SplittingBehavior` | `addSplitExceptions` correctly splits segments at split dates |
| `testCountUsableWorkdays_VariousRanges` | `countUsableWorkdays` counts correctly for 3-day, 6-day, and 7-day schedules, including exclusions |
| `testAllCategoriesInvalid_NoCrash` | Zero-week categories produce no exceptions without throwing an error |
| `testGenerateScheduleExceptions_MultipleValidInputs` | Batch processing of two valid inputs returns two wrappers |
| `testGenerateScheduleExceptions_MixedValidAndInvalidInputs` | Batch processing of valid + invalid input returns one success and one error |
| `testOnsiteGapClampedToInputDateRange` | Onsite gap exception and all generated exceptions remain within input start/end boundaries |
| `testPostWeeksConstrainsPostDateRange` | Post range is limited by `postWeeks` and does not extend to schedule end unless capped behavior requires it |
| `testGenerateScheduleExceptions_TwoValidInputs_NoErrors` | Two valid inputs both return wrappers with no errors |
| `testCapacityCapAndOverflowDropped_NoError` | Per-day hours are capped at 24, overflow beyond capacity is dropped, and no error is returned |

