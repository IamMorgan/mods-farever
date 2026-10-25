import farmer.FarmPlan;

class FarmPlanTest {
    static var failed = 0;

    static function check(ok:Bool, what:String):Void {
        if (!ok) { failed++; Sys.println("FAIL: " + what); }
    }

    static function main():Void {
        var plan = new FarmPlan();
        check(!plan.hasWork(), "empty plan has no work");
        plan.toggle(false, "Copper");
        check(plan.isPicked(false, "Copper") && !plan.isPicked(true, "Copper"), "toggle picks in one list only");
        check(plan.count(false, "Copper") == FarmPlan.DEFAULT_COUNT, "default count");
        plan.setCount(false, "Copper", 5);
        check(!plan.credit("Copper", 2), "partial credit");
        check(plan.count(false, "Copper") == 3, "counter goes down");
        check(plan.credit("Copper", 10), "reaching zero is reported");
        check(plan.count(false, "Copper") == 0 && !plan.resourcesLeft(), "no negative counter");
        plan.toggle(true, "Fang");
        plan.setCount(true, "Fang", 7);
        plan.targetLevel = 12;
        plan.recycle = true;
        plan.recycleQualities[2] = true;
        plan.clearBag = true;
        var copy = FarmPlan.fromJson(plan.toJson());
        check(copy.count(true, "Fang") == 7 && copy.targetLevel == 12 && copy.clearBag, "json round trip");
        check(copy.recyclesRarity("Epic") && !copy.recyclesRarity("Rare"), "recycled rarities");
        plan.recycle = false;
        check(!plan.recyclesRarity("Epic"), "recycling off");
        check(FarmPlan.fromJson("not json").hasWork() == false, "bad json gives an empty plan");
        plan.setCount(true, "Fang", 1000000);
        check(plan.count(true, "Fang") == FarmPlan.MAX_COUNT, "count is capped");
        if (failed > 0) Sys.exit(1);
        Sys.println("FarmPlanTest ok");
    }
}
