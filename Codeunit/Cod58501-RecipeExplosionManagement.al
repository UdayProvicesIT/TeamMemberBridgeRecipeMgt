codeunit 58501 "Recipe Explosion Management"
{
    var
        Math: Codeunit Math;

    // Find recipe for item based on location & default
    procedure FindRecipeForItem(
        LocationCode: Code[10];
        ItemNo: Code[20]): Code[20]
    var
        RecipeHeader: Record "Recipe Header";
        RecipeAssignedLocation: Record "Recipe Assigned Location";
    begin
        RecipeHeader.SetCurrentKey("Final Item No.", "Valid From");
        RecipeHeader.SetRange("Final Item No.", ItemNo);
        RecipeHeader.SetRange(Status, RecipeHeader.Status::Active);
        RecipeHeader.SetFilter("Valid From", '<=%1', WorkDate());
        RecipeHeader.SetAscending("Valid From", false);

        if RecipeHeader.FindFirst() then
            repeat
                if RecipeAssignedLocation.Get(
                    RecipeHeader."Recipe No.",
                    LocationCode)
                then
                    exit(RecipeHeader."Recipe No.");
            until RecipeHeader.Next() = 0;

        RecipeHeader.SetRange("Default Recipe", true);
        if RecipeHeader.FindFirst() then
            exit(RecipeHeader."Recipe No.");

        exit('');
    end;

    // Explode recipe recursively (BASE quantities only)
    procedure ExplodeRecipeLines(
        LocationCode: Code[10];
        RecipeHeader: Record "Recipe Header";
        RequiredQtyBase: Decimal;
        var VisitedRecipeNos: List of [Code[20]];
        var ItemQtyBaseMap: Dictionary of [Code[20], Decimal])
    var
        RecipeLine: Record "Recipe Line";
        BatchFactor: Decimal;
    begin
        if RequiredQtyBase = 0 then
            exit;

        RecipeHeader.TestField("Batch Size (Base)");

        BatchFactor :=
            RequiredQtyBase / RecipeHeader."Batch Size (Base)";

        RecipeLine.SetRange("Recipe No.", RecipeHeader."Recipe No.");
        if RecipeLine.FindSet() then
            repeat
                HandleRecipeLine(
                    LocationCode,
                    RecipeHeader,
                    RecipeLine,
                    BatchFactor,
                    VisitedRecipeNos,
                    ItemQtyBaseMap);
            until RecipeLine.Next() = 0;
    end;

    // Handle single recipe line
    local procedure HandleRecipeLine(
        LocationCode: Code[10];
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        BatchFactor: Decimal;
        var VisitedRecipeNos: List of [Code[20]];
        var ItemQtyBaseMap: Dictionary of [Code[20], Decimal])
    var
        Item: Record Item;
        ChildRecipeHeader: Record "Recipe Header";
        ChildRecipeNo: Code[20];
        RequiredQtyBase: Decimal;
    begin
        Item.Get(RecipeLine."Item No.");

        // ATO item → recurse
        if (Item."Replenishment System" = Item."Replenishment System"::Assembly) and
           (Item."Assembly Policy" = Item."Assembly Policy"::"Assemble-to-Order")
        then begin
            ChildRecipeNo :=
                FindRecipeForItem(LocationCode, Item."No.");

            ChildRecipeHeader.Get(ChildRecipeNo);

            if VisitedRecipeNos.IndexOf(ChildRecipeHeader."Recipe No.") > 0 then
                Error('Circular recipe reference detected.');

            VisitedRecipeNos.Add(ChildRecipeHeader."Recipe No.");

            ExplodeRecipeLines(
                LocationCode,
                ChildRecipeHeader,
                RecipeLine."Quantity per Batch (Base)" * BatchFactor,
                VisitedRecipeNos,
                ItemQtyBaseMap);

            VisitedRecipeNos.Remove(ChildRecipeHeader."Recipe No.");
            exit;
        end;

        // RM / ATS item
        RequiredQtyBase :=
            RecipeLine."Quantity per Batch (Base)" * BatchFactor;

        ApplySubstitutionWithPriority(
            LocationCode,
            RecipeHeader,
            RecipeLine,
            RequiredQtyBase,
            ItemQtyBaseMap);
    end;

    // Apply substitution policy with priority
    procedure ApplySubstitutionWithPriority(
        LocationCode: Code[10];
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        RequiredQtyBase: Decimal;
        var ItemQtyBaseMap: Dictionary of [Code[20], Decimal])
    var
        RecipeSubstituteItem: Record "Recipe Substitute Item";
        RemainingQtyBase: Decimal;
        UsedQtyBase: Decimal;
        MainAvailableQtyBase: Decimal;
        SubstituteAvailableQtyBase: Decimal;
    begin
        RemainingQtyBase := RequiredQtyBase;

        MainAvailableQtyBase :=
            GetAvailableQtyBase(
                RecipeLine."Item No.",
                LocationCode);

        RecipeSubstituteItem.SetRange("Recipe No.", RecipeHeader."Recipe No.");
        RecipeSubstituteItem.SetRange("Recipe Line No.", RecipeLine."Line No.");
        RecipeSubstituteItem.SetCurrentKey("Priority");
        RecipeSubstituteItem.Ascending(true);

        if RecipeSubstituteItem.FindSet() then
            repeat
                if RemainingQtyBase = 0 then
                    break;

                SubstituteAvailableQtyBase :=
                    GetAvailableQtyBase(
                        RecipeSubstituteItem."Substitute Item No.",
                        LocationCode);

                if SubstituteAvailableQtyBase <= 0 then
                    continue;

                case RecipeSubstituteItem."Use Policy" of

                    RecipeSubstituteItem."Use Policy"::"Sufficient Substitute Item Availability":
                        begin
                            UsedQtyBase :=
                                Math.Min(SubstituteAvailableQtyBase, RemainingQtyBase);

                            AddToItemQtyMap(
                                ItemQtyBaseMap,
                                RecipeSubstituteItem."Substitute Item No.",
                                UsedQtyBase);

                            RemainingQtyBase -= UsedQtyBase;
                        end;

                    RecipeSubstituteItem."Use Policy"::"Insufficient Main Item Availability":
                        begin
                            if MainAvailableQtyBase < RemainingQtyBase then begin
                                AddToItemQtyMap(
                                    ItemQtyBaseMap,
                                    RecipeSubstituteItem."Substitute Item No.",
                                    RemainingQtyBase);
                                RemainingQtyBase := 0;
                            end;
                        end;
                end;

            until RecipeSubstituteItem.Next() = 0;

        // Final fallback → MAIN item
        if RemainingQtyBase > 0 then
            AddToItemQtyMap(
                ItemQtyBaseMap,
                RecipeLine."Item No.",
                RemainingQtyBase);
    end;

    local procedure AddToItemQtyMap(
        var ItemQtyBaseMap: Dictionary of [Code[20], Decimal];
        ItemNo: Code[20];
        QtyBase: Decimal)
    var
        ExistingQtyBase: Decimal;
    begin
        if QtyBase <= 0 then
            exit;

        if ItemQtyBaseMap.ContainsKey(ItemNo) then begin
            ItemQtyBaseMap.Get(ItemNo, ExistingQtyBase);
            ItemQtyBaseMap.Set(ItemNo, ExistingQtyBase + QtyBase);
        end else
            ItemQtyBaseMap.Add(ItemNo, QtyBase);
    end;

    local procedure GetAvailableQtyBase(
        ItemNo: Code[20];
        LocationCode: Code[10]): Decimal
    var
        Item: Record Item;
    begin
        Item.Get(ItemNo);
        Item.SetRange("Location Filter", LocationCode);
        Item.CalcFields(Inventory);
        exit(Item.Inventory);
    end;
}
