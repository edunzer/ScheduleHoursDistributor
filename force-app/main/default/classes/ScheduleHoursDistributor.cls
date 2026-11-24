public with sharing class ScheduleHoursDistributor {
    private static final Boolean DEBUG = false;
    private static final Decimal MAX_HOURS_PER_DAY = 24;
    private static final Integer MAX_REDISTRIBUTION_PASSES = 4;
    // Onsite periods shorter than this (and fully inside the schedule) get an onsite gap week and a Post category.
    private static final Integer ONSITE_MAX_DAYS = 30;
    // A known Monday. Weekday math is relative to it, so results never depend on the running user's locale.
    private static final Date REFERENCE_MONDAY = Date.newInstance(2024, 1, 1);

    @InvocableMethod(label='Generate Category Schedule Exceptions' description='Generates schedule exception records for a category, skipping holidays.')
    public static List<ScheduleExceptionOutputWrapper> generateCategoryScheduleExceptions(List<ScheduleInput> inputList) {
        List<ScheduleExceptionOutputWrapper> outputList = new List<ScheduleExceptionOutputWrapper>();
        if (inputList == null || inputList.isEmpty()) {
            return outputList;
        }

        for (ScheduleInput input : inputList) {
            try {
                outputList.add(processSingleSchedule(input));
            } catch (Exception e) {
                outputList.add(createErrorWrapper('Error: ' + e.getMessage()));
            }
        }
        return outputList;
    }

    // Processes a single ScheduleInput and returns its output wrapper
    private static ScheduleExceptionOutputWrapper processSingleSchedule(ScheduleInput input) {
        String validationError = validate(input);
        if (validationError != null) {
            return createErrorWrapper(validationError);
        }

        Integer workDays = boundWorkDays(input.numberOfWorkDays);
        // Existing exceptions are only used to block dates; they are never returned.
        Set<Date> holidayDates = extractHolidayDates(input.existingExceptions);

        // 1. Onsite gap: the Monday-Sunday week containing onsiteStartDate.
        Date gapStart = null;
        Date gapEnd = null;
        if (isOnsiteNeeded(input)) {
            gapStart = mondayOfWeek(input.onsiteStartDate);
            gapEnd = gapStart.addDays(6);
        }

        // 2. Category date ranges.
        List<CategoryPlan> plans = buildCategoryPlans(input, gapStart, gapEnd);

        // 3. Usable days per category (holidays and onsite gap days excluded), then percentage shares.
        Set<Date> allSplits = new Set<Date>(holidayDates);
        if (gapStart != null) {
            for (Date d = gapStart; d <= gapEnd; d = d.addDays(1)) {
                allSplits.add(d);
            }
        }
        for (CategoryPlan plan : plans) {
            plan.usableDays = plan.hasRange() ? countUsableWorkdays(plan.actualStart, plan.actualEnd, allSplits, workDays) : 0;
        }
        normalizePercentages(plans);

        // 4. Capacity-aware hour allocation.
        Decimal unscheduledHours = allocateHours(plans, input.numberOfHours);

        // 5. Build exceptions: onsite gap (zero hours) first, then categories in order.
        List<pse__Schedule_Exception__c> allExceptions = new List<pse__Schedule_Exception__c>();
        if (gapStart != null) {
            Date gapSegStart = gapStart < input.startDate ? input.startDate : gapStart;
            Date gapSegEnd = gapEnd > input.endDate ? input.endDate : gapEnd;
            allExceptions.addAll(buildSplitExceptions(gapSegStart, gapSegEnd, 0, workDays, input.scheduleId, input.startDate, input.endDate, holidayDates));
        }
        for (CategoryPlan plan : plans) {
            if (!plan.hasRange()) {
                continue;
            }
            Date rangeStart = plan.actualStart;
            if (plan.extraCentDays > 0) {
                // The first extraCentDays usable days carry one extra cent so the category total is exact.
                Date lastExtraDay = nthUsableDay(plan.actualStart, plan.actualEnd, allSplits, workDays, plan.extraCentDays);
                allExceptions.addAll(
                    buildSplitExceptions(rangeStart, lastExtraDay, plan.hoursPerDay + 0.01, workDays, input.scheduleId, input.startDate, input.endDate, allSplits)
                );
                rangeStart = lastExtraDay.addDays(1);
            }
            allExceptions.addAll(
                buildSplitExceptions(rangeStart, plan.actualEnd, plan.hoursPerDay, workDays, input.scheduleId, input.startDate, input.endDate, allSplits)
            );
        }

        if (DEBUG) {
            for (CategoryPlan plan : plans) {
                System.debug(plan);
            }
            System.debug('allSplits=' + allSplits + ', unscheduledHours=' + unscheduledHours);
        }

        return new ScheduleExceptionOutputWrapper(allExceptions, null);
    }

    // Returns an error message for invalid input, or null when the input is valid.
    private static String validate(ScheduleInput input) {
        if (input == null) return 'Error: Input cannot be null.';
        if (input.scheduleId == null) return 'Error: Schedule ID cannot be null.';
        if (input.startDate == null) return 'Error: Start Date cannot be null.';
        if (input.endDate == null) return 'Error: End Date cannot be null.';
        if (input.startDate > input.endDate) return 'Error: Start Date must be on or before End Date.';
        if (input.numberOfHours == null) return 'Error: Number of Hours cannot be null.';
        if (input.numberOfHours <= 0) return 'Error: Number of Hours must be greater than zero.';
        if (input.numberOfWorkDays == null) return 'Error: Number of Work Days cannot be null.';
        if (input.cat1Weeks == null || input.cat2Weeks == null || input.cat3Weeks == null || input.postWeeks == null) {
            return 'Error: Week values cannot be null.';
        }
        if (input.cat1Weeks < 0 || input.cat2Weeks < 0 || input.cat3Weeks < 0 || input.postWeeks < 0) {
            return 'Error: Week values cannot be negative.';
        }
        if (input.cat1Percentage == null || input.cat2Percentage == null || input.cat3Percentage == null || input.postPercentage == null) {
            return 'Error: Percentage values cannot be null.';
        }
        if (input.cat1Percentage < 0 || input.cat2Percentage < 0 || input.cat3Percentage < 0 || input.postPercentage < 0) {
            return 'Error: Percentage values cannot be negative.';
        }
        if ((input.onsiteStartDate == null) != (input.onsiteEndDate == null)) {
            return 'Error: Both Onsite Start Date and Onsite End Date must be provided.';
        }
        if (input.onsiteStartDate != null && input.onsiteStartDate > input.onsiteEndDate) {
            return 'Error: Onsite Start Date must be on or before Onsite End Date.';
        }
        return null;
    }

    // Onsite handling applies only when the onsite period is short and fully inside the schedule.
    private static Boolean isOnsiteNeeded(ScheduleInput input) {
        if (input.onsiteStartDate == null || input.onsiteEndDate == null) {
            return false;
        }
        Integer onsiteDays = input.onsiteStartDate.daysBetween(input.onsiteEndDate) + 1;
        return onsiteDays < ONSITE_MAX_DAYS && input.onsiteStartDate >= input.startDate && input.onsiteEndDate <= input.endDate;
    }

    // Builds the category plans in output order (cat1, cat2, cat3, post).
    // Post (onsite only) starts the day after the onsite gap week. Cat3, Cat2 and Cat1 are laid out backwards
    // from the day before the gap week (when Post applies) or from the schedule end date.
    private static List<CategoryPlan> buildCategoryPlans(ScheduleInput input, Date gapStart, Date gapEnd) {
        CategoryPlan post = new CategoryPlan('post', input.postPercentage);
        if (gapStart != null) {
            Integer postDays = weeksToDays(input.postWeeks);
            if (postDays > 0) {
                Date postStart = gapEnd.addDays(1);
                Date requestedPostEnd = postStart.addDays(postDays - 1);
                Date postEnd = requestedPostEnd < input.endDate ? requestedPostEnd : input.endDate;
                if (postStart <= postEnd) {
                    post.setRange(postStart, postEnd, input);
                }
            }
        }

        // Each category ends the day before the following one starts.
        Date followingStart = post.valid ? gapStart : input.endDate.addDays(1);

        CategoryPlan cat3 = new CategoryPlan('cat3', input.cat3Percentage);
        cat3.setRange(followingStart.addDays(-weeksToDays(input.cat3Weeks)), followingStart.addDays(-1), input);

        CategoryPlan cat2 = new CategoryPlan('cat2', input.cat2Percentage);
        cat2.setRange(cat3.rangeStart.addDays(-weeksToDays(input.cat2Weeks)), cat3.rangeStart.addDays(-1), input);

        CategoryPlan cat1 = new CategoryPlan('cat1', input.cat1Percentage);
        cat1.setRange(cat2.rangeStart.addDays(-weeksToDays(input.cat1Weeks)), cat2.rangeStart.addDays(-1), input);

        return new List<CategoryPlan>{ cat1, cat2, cat3, post };
    }

    // Normalizes percentages proportionally across categories that have usable days: each category's
    // share is its percentage divided by the total of those categories' percentages, so the configured
    // ratios are preserved whatever the sum. If they are all zero, the hours are split evenly.
    // Categories without usable days get a zero share. pct is the share as a percentage (2 dp,
    // rounding residual on the last category) for reporting.
    private static void normalizePercentages(List<CategoryPlan> plans) {
        List<CategoryPlan> usablePlans = new List<CategoryPlan>();
        Decimal sumPct = 0;
        for (CategoryPlan plan : plans) {
            if (plan.usableDays > 0) {
                usablePlans.add(plan);
                sumPct += plan.inputPct;
            }
        }
        if (usablePlans.isEmpty()) {
            return;
        }

        Decimal sumRounded = 0;
        for (CategoryPlan plan : usablePlans) {
            plan.share = sumPct > 0 ? plan.inputPct / sumPct : 1.0 / usablePlans.size();
            plan.pct = (plan.share * 100).setScale(2, System.RoundingMode.HALF_UP);
            sumRounded += plan.pct;
        }
        CategoryPlan last = usablePlans[usablePlans.size() - 1];
        last.pct += 100 - sumRounded;
    }

    // Allocates hours to categories with usable days: first by share, capped at capacity
    // (usableDays x MAX_HOURS_PER_DAY), then rolls overflow into categories with free capacity.
    // Sets allocatedHours and hoursPerDay on each plan and returns the hours that could not be scheduled.
    private static Decimal allocateHours(List<CategoryPlan> plans, Decimal numberOfHours) {
        List<CategoryPlan> usablePlans = new List<CategoryPlan>();
        for (CategoryPlan plan : plans) {
            if (plan.usableDays > 0) {
                usablePlans.add(plan);
                plan.capacity = plan.usableDays * MAX_HOURS_PER_DAY;
            }
        }

        Decimal overflowHours = numberOfHours;

        // First pass: share of the requested hours, capped by capacity.
        for (CategoryPlan plan : usablePlans) {
            Decimal target = numberOfHours * plan.share;
            plan.allocatedHours = target <= plan.capacity ? target : plan.capacity;
            overflowHours -= plan.allocatedHours;
        }

        // Additional passes: roll overflow into categories with remaining capacity.
        Integer passes = 0;
        while (overflowHours > 0 && passes < MAX_REDISTRIBUTION_PASSES) {
            Decimal totalFree = 0;
            for (CategoryPlan plan : usablePlans) {
                if (plan.freeCapacity() > 0) totalFree += plan.freeCapacity();
            }
            if (totalFree <= 0) {
                break;
            }

            Decimal distributed = 0;
            for (CategoryPlan plan : usablePlans) {
                Decimal free = plan.freeCapacity();
                if (free <= 0) continue;
                Decimal share = overflowHours * (free / totalFree);
                Decimal add = share <= free ? share : free;
                plan.allocatedHours += add;
                distributed += add;
            }

            if (distributed <= 0) {
                break;
            }
            overflowHours -= distributed;
            passes++;
        }

        // Convert to whole cents so the 2-decimal per-day hours add up exactly to the scheduled total.
        Decimal scheduledHours = 0;
        for (CategoryPlan plan : usablePlans) {
            scheduledHours += plan.allocatedHours;
        }
        Long remainingCents = (scheduledHours * 100).round(System.RoundingMode.HALF_UP);
        for (CategoryPlan plan : usablePlans) {
            plan.allocatedCents = (plan.allocatedHours * 100).round(System.RoundingMode.DOWN);
            remainingCents -= plan.allocatedCents;
        }
        // Largest-remainder method: leftover cents go to the categories whose truncated fraction was largest.
        while (remainingCents > 0) {
            CategoryPlan best = null;
            Decimal bestFraction = null;
            for (CategoryPlan plan : usablePlans) {
                Decimal fraction = plan.allocatedHours * 100 - plan.allocatedCents;
                if (plan.allocatedCents < plan.capacity * 100 && (bestFraction == null || fraction > bestFraction)) {
                    best = plan;
                    bestFraction = fraction;
                }
            }
            if (best == null) {
                break;
            }
            best.allocatedCents = best.allocatedCents + 1;
            remainingCents--;
        }

        // Within a category, every usable day gets baseCents and the first extraCentDays usable days get one cent more.
        Decimal totalScheduled = 0;
        for (CategoryPlan plan : usablePlans) {
            Long baseCents = plan.allocatedCents / plan.usableDays;
            plan.extraCentDays = (plan.allocatedCents - baseCents * plan.usableDays).intValue();
            plan.hoursPerDay = Decimal.valueOf(baseCents).divide(100, 2);
            plan.allocatedHours = Decimal.valueOf(plan.allocatedCents).divide(100, 2);
            totalScheduled += plan.allocatedHours;
        }

        return numberOfHours - totalScheduled;
    }

    // Returns the n-th (1-based) usable day in [startDate, endDate], or endDate if there are fewer than n.
    private static Date nthUsableDay(Date startDate, Date endDate, Set<Date> excludeDates, Integer workDays, Integer n) {
        Integer seen = 0;
        for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
            if (isScheduledWorkday(d, workDays) && !excludeDates.contains(d)) {
                seen++;
                if (seen == n) {
                    return d;
                }
            }
        }
        return endDate;
    }

    // Week counts are converted to whole days (weeks x 7, decimals truncated).
    private static Integer weeksToDays(Decimal weeks) {
        return Integer.valueOf(weeks * 7);
    }

    // Helper: create a single error wrapper
    private static ScheduleExceptionOutputWrapper createErrorWrapper(String errorMessage) {
        return new ScheduleExceptionOutputWrapper(new List<pse__Schedule_Exception__c>(), errorMessage);
    }

    // Helper: Extracts all holiday dates from existing exceptions
    public static Set<Date> extractHolidayDates(List<pse__Schedule_Exception__c> existingExceptions) {
        Set<Date> holidayDates = new Set<Date>();
        if (existingExceptions != null) {
            for (pse__Schedule_Exception__c exc : existingExceptions) {
                if (exc == null || exc.pse__Date__c == null) continue;
                Date start = exc.pse__Date__c;
                Date endDate = exc.pse__End_Date__c == null ? start : exc.pse__End_Date__c;
                for (Date d = start; d <= endDate; d = d.addDays(1)) {
                    holidayDates.add(d);
                }
            }
        }
        return holidayDates;
    }

    // Helper: Creates and returns a single schedule exception record
    public static pse__Schedule_Exception__c createScheduleException(Id scheduleId, Date startDate, Date endDate, Integer workDays, Decimal hoursPerDay) {
        Integer boundedWorkDays = boundWorkDays(workDays);
        return new pse__Schedule_Exception__c(
            pse__Schedule__c = scheduleId,
            pse__Date__c = startDate,
            pse__End_Date__c = endDate,
            pse__Monday_Hours__c = (boundedWorkDays >= 1) ? hoursPerDay : 0,
            pse__Tuesday_Hours__c = (boundedWorkDays >= 2) ? hoursPerDay : 0,
            pse__Wednesday_Hours__c = (boundedWorkDays >= 3) ? hoursPerDay : 0,
            pse__Thursday_Hours__c = (boundedWorkDays >= 4) ? hoursPerDay : 0,
            pse__Friday_Hours__c = (boundedWorkDays >= 5) ? hoursPerDay : 0,
            pse__Saturday_Hours__c = (boundedWorkDays >= 6) ? hoursPerDay : 0,
            pse__Sunday_Hours__c = (boundedWorkDays >= 7) ? hoursPerDay : 0
        );
    }

    // Helper: Adds split exceptions for a category, splitting at every holiday and onsite gap day.
    // Each created exception is added to both allExceptions and catList.
    public static void addSplitExceptions(
        Date segStart,
        Date segEnd,
        Decimal hoursPerDay,
        Integer workDays,
        Id scheduleId,
        Date inputStart,
        Date inputEnd,
        Set<Date> allSplits,
        List<pse__Schedule_Exception__c> allExceptions,
        List<pse__Schedule_Exception__c> catList
    ) {
        List<pse__Schedule_Exception__c> created = buildSplitExceptions(segStart, segEnd, hoursPerDay, workDays, scheduleId, inputStart, inputEnd, allSplits);
        allExceptions.addAll(created);
        catList.addAll(created);
    }

    // Returns one exception per uninterrupted run of days in [segStart, segEnd] that is inside
    // [inputStart, inputEnd] and not in splitDates.
    private static List<pse__Schedule_Exception__c> buildSplitExceptions(
        Date segStart,
        Date segEnd,
        Decimal hoursPerDay,
        Integer workDays,
        Id scheduleId,
        Date inputStart,
        Date inputEnd,
        Set<Date> splitDates
    ) {
        List<pse__Schedule_Exception__c> created = new List<pse__Schedule_Exception__c>();
        Date runStart = null;
        for (Date d = segStart; d <= segEnd; d = d.addDays(1)) {
            Boolean isOpen = !splitDates.contains(d) && d >= inputStart && d <= inputEnd;
            if (isOpen && runStart == null) {
                runStart = d;
            } else if (!isOpen && runStart != null) {
                created.add(createScheduleException(scheduleId, runStart, d.addDays(-1), workDays, hoursPerDay));
                runStart = null;
            }
        }
        if (runStart != null) {
            created.add(createScheduleException(scheduleId, runStart, segEnd, workDays, hoursPerDay));
        }
        return created;
    }

    // Helper: Counts usable workdays between two dates, excluding holidays and onsite gap days.
    // Workday pattern follows numberOfWorkDays: 1=Mon only ... 5=Mon-Fri, 6=Mon-Sat, 7=Mon-Sun.
    public static Integer countUsableWorkdays(Date start, Date endDate, Set<Date> excludeDates, Integer numberOfWorkDays) {
        Integer boundedWorkDays = boundWorkDays(numberOfWorkDays);
        Integer count = 0;
        for (Date d = start; d <= endDate; d = d.addDays(1)) {
            if (isScheduledWorkday(d, boundedWorkDays) && !excludeDates.contains(d)) {
                count++;
            }
        }
        return count;
    }

    // Backward-compatible overload defaults to Mon-Fri behavior.
    public static Integer countUsableWorkdays(Date start, Date endDate, Set<Date> excludeDates) {
        return countUsableWorkdays(start, endDate, excludeDates, 5);
    }

    // Helper: Returns day-of-week where Monday=1 and Sunday=7, independent of the user's locale.
    public static Integer getNormalizedDayOfWeek(Date d) {
        Integer offset = Math.mod(REFERENCE_MONDAY.daysBetween(d), 7);
        if (offset < 0) offset += 7;
        return offset + 1;
    }

    // Helper: Returns the Monday of the week containing d.
    private static Date mondayOfWeek(Date d) {
        return d.addDays(1 - getNormalizedDayOfWeek(d));
    }

    // Helper: Returns true if date is one of the configured workdays for the week.
    public static Boolean isScheduledWorkday(Date d, Integer numberOfWorkDays) {
        return getNormalizedDayOfWeek(d) <= boundWorkDays(numberOfWorkDays);
    }

    // Helper: Clamps workdays to supported range [1..7], defaulting to 5 when null.
    private static Integer boundWorkDays(Integer numberOfWorkDays) {
        Integer boundedWorkDays = numberOfWorkDays == null ? 5 : numberOfWorkDays;
        if (boundedWorkDays < 1) boundedWorkDays = 1;
        if (boundedWorkDays > 7) boundedWorkDays = 7;
        return boundedWorkDays;
    }

    // Helper: Returns true if the date is a weekday (Mon-Fri)
    public static Boolean isWeekday(Date d) {
        return getNormalizedDayOfWeek(d) <= 5;
    }

    // Working state for one category (cat1, cat2, cat3 or post) while a schedule is processed.
    private class CategoryPlan {
        public String key;
        public Decimal inputPct;
        // Raw range before clipping to the schedule (may be empty when weeks = 0).
        public Date rangeStart;
        public Date rangeEnd;
        public Boolean valid = false;
        // Range clipped to the schedule's start/end dates.
        public Date actualStart;
        public Date actualEnd;
        // Fraction (0..1) of the requested hours this category targets, and the same as a percentage.
        public Decimal share = 0;
        public Decimal pct = 0;
        public Integer usableDays = 0;
        public Decimal capacity = 0;
        public Decimal allocatedHours = 0;
        public Long allocatedCents = 0;
        // Base hours per usable day; the first extraCentDays usable days get hoursPerDay + 0.01.
        public Decimal hoursPerDay = 0;
        public Integer extraCentDays = 0;

        public CategoryPlan(String key, Decimal inputPct) {
            this.key = key;
            this.inputPct = inputPct;
        }

        public void setRange(Date startDate, Date endDate, ScheduleInput input) {
            rangeStart = startDate;
            rangeEnd = endDate;
            // A zero-week category has startDate = endDate + 1 and is never valid.
            valid = startDate <= endDate && endDate >= input.startDate && startDate <= input.endDate;
            if (valid) {
                actualStart = startDate > input.startDate ? startDate : input.startDate;
                actualEnd = endDate < input.endDate ? endDate : input.endDate;
            }
        }

        public Boolean hasRange() {
            return valid && actualStart <= actualEnd;
        }

        public Decimal freeCapacity() {
            return capacity - allocatedHours;
        }
    }

    // Wrapper class: Holds output schedule exceptions and calculated values
    public class ScheduleExceptionOutputWrapper {
        @InvocableVariable(label='Schedule Exceptions' description='List of Schedule Exception records')
        public List<pse__Schedule_Exception__c> scheduleExceptions;

        @InvocableVariable(label='Error Message' description='Error encountered during execution')
        public String errorMessage;

        public ScheduleExceptionOutputWrapper(List<pse__Schedule_Exception__c> exceptions, String error) {
            this.scheduleExceptions = exceptions;
            this.errorMessage = error;
        }
    }

    // Input wrapper class: Holds parameters from Flow for schedule generation
    public class ScheduleInput {
        @InvocableVariable(label='Onsite Start Date')
        public Date onsiteStartDate;
        @InvocableVariable(label='Onsite End Date')
        public Date onsiteEndDate;
        @InvocableVariable(label='Schedule ID')
        public Id scheduleId;
        @InvocableVariable(label='Start Date')
        public Date startDate;
        @InvocableVariable(label='End Date')
        public Date endDate;
        @InvocableVariable(label='Number of Hours')
        public Decimal numberOfHours;
        @InvocableVariable(label='Number of Work Days')
        public Integer numberOfWorkDays;

        @InvocableVariable(label='Category 1 Weeks')
        public Decimal cat1Weeks;
        @InvocableVariable(label='Category 2 Weeks')
        public Decimal cat2Weeks;
        @InvocableVariable(label='Category 3 Weeks')
        public Decimal cat3Weeks;
        @InvocableVariable(label='Post Weeks')
        public Decimal postWeeks;

        @InvocableVariable(label='Category 1 Percentage')
        public Decimal cat1Percentage;
        @InvocableVariable(label='Category 2 Percentage')
        public Decimal cat2Percentage;
        @InvocableVariable(label='Category 3 Percentage')
        public Decimal cat3Percentage;
        @InvocableVariable(label='Post Percentage')
        public Decimal postPercentage;

        @InvocableVariable(label='Existing Schedule Exceptions')
        public List<pse__Schedule_Exception__c> existingExceptions;
    }
}
