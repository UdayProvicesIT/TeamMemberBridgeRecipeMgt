codeunit 58501 "Replace Main Item By Sub. Item"
{
    // Check inventory at a location
    procedure HasSufficientInventory(ItemNo: Code[20]; Location: Code[10]; RequiredQty: Decimal): Boolean
    var
        Item: Record Item;
    begin
        Item.SetRange("No.", ItemNo);
        Item.SetRange("Location Filter", Location);

        if not Item.FindFirst() then
            exit(false);

        Item.CalcFields(Inventory);
        exit(Item.Inventory >= RequiredQty);
    end;


    // Find substitute item with enough stock
    procedure GetAvailableSubstitute(MainItem: Code[20]; Location: Code[10]; RequiredQty: Decimal): Code[20]
    var
        ItemSubstitution: Record "Item Substitution";
    begin
        ItemSubstitution.SetRange("No.", MainItem);
        ItemSubstitution.SetRange(Interchangeable, true);

        if ItemSubstitution.FindSet() then
            repeat
                if HasSufficientInventory(ItemSubstitution."Substitute No.", Location, RequiredQty) then
                    exit(ItemSubstitution."Substitute No.");
            until ItemSubstitution.Next() = 0;

        exit('');
    end;


    // High-level function → returns final item (main or substitute)
    procedure ResolveItemWithSubstitute(MainItem: Code[20]; Location: Code[10]; RequiredQty: Decimal): Code[20]
    var
        SubstituteNo: Code[20];
    begin
        if HasSufficientInventory(MainItem, Location, RequiredQty) then
            exit(MainItem);

        SubstituteNo := GetAvailableSubstitute(MainItem, Location, RequiredQty);

        if SubstituteNo <> '' then
            exit(SubstituteNo); // Use substitute

        exit(MainItem); // Fallback → return main item even when insufficient
    end;
}
