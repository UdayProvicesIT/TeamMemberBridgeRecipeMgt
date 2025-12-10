codeunit 58502 "Replace LIT Trans.LineByRecipe"
{
    var
        VisitedRecipes: List of [Code[20]];
        SubHelper: Codeunit "Replace Main Item By Sub. Item";

    //Replace Transfer BOM Explosion with Recipe Logic
    [EventSubscriber(ObjectType::Table, Database::"LIT TransferDoc Line",
        'OnBeforeExplodeTransferBOM', '', true, true)]
    local procedure UseRecipeInsteadOfLITBOM(
        var TransferLine: Record "LIT TransferDoc Line";
        var NewLineNo: Integer;
        var IsHandled: Boolean)
    var
        RecipeMgtSetup: Record "Recipe Management Setup";
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        Item: Record Item;
        RecipeNo: Code[20];
        UnitOfMeasureMgt: Codeunit "Unit of Measure Management";
        FromFactor: Decimal;
        ToFactor: Decimal;
        BatchSizeInBase: Decimal;
        QtyInBase: Decimal;
        BatchFactor: Decimal;
        LineNo: Integer;
    begin
        // Setup validation
        if not RecipeMgtSetup.Get() then
            exit;

        if not RecipeMgtSetup."Overwrite Assembly BOMs" then
            exit;

        // Only top-level lines
        if TransferLine."LIT Parent Item" <> '' then
            exit;

        // Full override
        IsHandled := true;

        TransferLine.TestField("LIT Item No.");
        Item.Get(TransferLine."LIT Item No.");

        // Find recipe (location → default → fallback)
        RecipeNo := FindRecipeForItem(
                        TransferLine."LIT Transfer-from Code",
                        TransferLine."LIT Item No.");

        if RecipeNo = '' then
            Error('No active recipe found for item %1.', TransferLine."LIT Item No.");

        if not RecipeHeader.Get(RecipeNo) then
            Error('Recipe %1 not found.', RecipeNo);

        if RecipeHeader."Batch Size" = 0 then
            Error('Recipe %1 has Batch Size = 0.', RecipeHeader."Recipe No.");

        // UOM Conversion → BatchFactor
        FromFactor :=
            UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, RecipeHeader."Batch UOM");
        ToFactor :=
            UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure");

        BatchSizeInBase := RecipeHeader."Batch Size" * (FromFactor / ToFactor);

        // Convert transfer quantity to base UOM
        FromFactor :=
            UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, TransferLine."LIT UOM");

        QtyInBase := TransferLine."LIT Quantity" * (FromFactor / ToFactor);
        BatchFactor := QtyInBase / BatchSizeInBase;

        // Prepare recursion stack
        Clear(VisitedRecipes);
        VisitedRecipes.Add(RecipeHeader."Recipe No.");

        // Remove old exploded lines
        DeleteRecipeGeneratedLines(TransferLine);

        // Begin explosion
        LineNo := TransferLine."LIT TransferDoc Line No.";

        RecipeLine.SetRange("Recipe No.", RecipeHeader."Recipe No.");
        if RecipeLine.FindSet() then
            repeat
                InsertTransferLineForRecipe(
                    TransferLine,
                    RecipeHeader,
                    RecipeLine,
                    BatchFactor,
                    LineNo);
            until RecipeLine.Next() = 0;
    end;


    local procedure FindRecipeForItem(LocationCode: Code[10]; ItemNo: Code[20]): Code[20]
    var
        RecipeHeader: Record "Recipe Header";
        RecipeAssignedLocation: Record "Recipe Assigned Location";
    begin
        // Assigned
        RecipeAssignedLocation.SetRange("Location Code", LocationCode);
        if RecipeAssignedLocation.FindSet() then
            repeat
                if RecipeHeader.Get(RecipeAssignedLocation."Recipe No.") then
                    if (RecipeHeader.Status = RecipeHeader.Status::Active) and
                       (RecipeHeader."Final Item No." = ItemNo)
                    then
                        exit(RecipeHeader."Recipe No.");
            until RecipeAssignedLocation.Next() = 0;

        // Default active
        RecipeHeader.Reset();
        RecipeHeader.SetRange("Final Item No.", ItemNo);
        RecipeHeader.SetRange("Default Recipe", true);
        RecipeHeader.SetRange(Status, RecipeHeader.Status::Active);
        if RecipeHeader.FindFirst() then
            exit(RecipeHeader."Recipe No.");

        // Fallback (any active recipe for item)
        RecipeHeader.Reset();
        RecipeHeader.SetRange("Final Item No.", ItemNo);
        if RecipeHeader.FindFirst() then
            exit(RecipeHeader."Recipe No.");

        exit('');
    end;


    // MULTI-LEVEL INSERTION (ATO explodes, ATS & RM inserted)
    local procedure InsertTransferLineForRecipe(
        SourceLITTransferDocLine: Record "LIT TransferDoc Line";
        SourceRecipeHeader: Record "Recipe Header";
        SourceRecipeLine: Record "Recipe Line";
        BatchFactor: Decimal;
        var LineNo: Integer)
    var
        Item: Record Item;
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        UnitOfMeasureMgt: Codeunit "Unit of Measure Management";
        FromFactor: Decimal;
        ToFactor: Decimal;
        RequiredBase: Decimal;
        CurrentBatchBase: Decimal;
        CurrentBatchFactor: Decimal;
    begin
        Item.Get(SourceRecipeLine."Item No.");

        // ATO → recursive explosion
        if (Item."Replenishment System" = Item."Replenishment System"::Assembly) and
           (Item."Assembly Policy" = Item."Assembly Policy"::"Assemble-to-Order")
        then begin
            RecipeHeader.SetRange("Final Item No.", Item."No.");
            RecipeHeader.SetRange("Default Recipe", true);
            RecipeHeader.SetRange(Status, RecipeHeader.Status::Active);
            if not RecipeHeader.FindFirst() then
                Error('Recipe missing for SFG %1.', Item."No.");

            // Circular reference protection
            if VisitedRecipes.IndexOf(RecipeHeader."Recipe No.") > 0 then
                Error('Circular reference between %1 and %2.',
                      SourceRecipeHeader."Recipe No.", RecipeHeader."Recipe No.");

            VisitedRecipes.Add(RecipeHeader."Recipe No.");

            // Convert required qty → base
            FromFactor :=
                UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, SourceRecipeLine."Unit of Measure Code");
            ToFactor :=
                UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure");

            RequiredBase :=
                SourceRecipeLine."Quantity per Batch" * BatchFactor * (FromFactor / ToFactor);

            // Child batch size → base
            FromFactor :=
                UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, RecipeHeader."Batch UOM");
            ToFactor :=
                UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure");

            CurrentBatchBase :=
                RecipeHeader."Batch Size" * (FromFactor / ToFactor);

            CurrentBatchFactor := RequiredBase / CurrentBatchBase;

            // Explode child recipe
            RecipeLine.SetRange("Recipe No.", RecipeHeader."Recipe No.");
            if RecipeLine.FindSet() then
                repeat
                    InsertTransferLineForRecipe(
                        SourceLITTransferDocLine,
                        RecipeHeader,
                        RecipeLine,
                        CurrentBatchFactor,
                        LineNo);
                until RecipeLine.Next() = 0;

            VisitedRecipes.Remove(RecipeHeader."Recipe No.");
            exit;
        end;

        // ATS or RM → insert line
        LineNo += 10000;

        InsertRMIntoTransfer(
            SourceLITTransferDocLine,
            SourceRecipeLine,
            LineNo,
            BatchFactor);
    end;


    // DELETE prior exploded lines
    local procedure DeleteRecipeGeneratedLines(SourceLITTransferDocLine: Record "LIT TransferDoc Line")
    var
        LITTransferDocLine: Record "LIT TransferDoc Line";
    begin
        LITTransferDocLine.SetRange("LIT TransferDoc No.", SourceLITTransferDocLine."LIT TransferDoc No.");
        LITTransferDocLine.SetRange("LIT Parent Item", SourceLITTransferDocLine."LIT Item No.");
        LITTransferDocLine.DeleteAll();
    end;


    // INSERT FINAL RM/SFG LINE (with substitution support)
    local procedure InsertRMIntoTransfer(
     SourceLITTransferDocLine: Record "LIT TransferDoc Line";
     RecipeLine: Record "Recipe Line";
     NewLineNo: Integer;
     BatchFactor: Decimal)
    var
        LITTransferDocLine: Record "LIT TransferDoc Line";
        Item: Record Item;
        SubItem: Record Item;
        UnitOfMeasureMgt: Codeunit "Unit of Measure Management";
        FromFactor: Decimal;
        ToFactor: Decimal;
        RequiredQtyBase: Decimal;
        MainItemNo: Code[20];
        FinalItemNo: Code[20];
        FinalUOM: Code[10];
    begin
        MainItemNo := RecipeLine."Item No.";
        Item.Get(MainItemNo);

        // MAIN item required qty → base
        FromFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, RecipeLine."Unit of Measure Code");
        ToFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure");
        if ToFactor = 0 then
            ToFactor := 1;

        RequiredQtyBase :=
            RecipeLine."Quantity per Batch" * BatchFactor * (FromFactor / ToFactor);

        // Resolve substitute
        FinalItemNo :=
            SubHelper.ResolveItemWithSubstitute(
                MainItemNo,
                SourceLITTransferDocLine."LIT Transfer-from Code",
                RequiredQtyBase);

        SubItem.Get(FinalItemNo);

        // Pick correct UOM
        if FinalItemNo = MainItemNo then
            FinalUOM := RecipeLine."Unit of Measure Code"
        else
            FinalUOM := SubItem."Base Unit of Measure";

        // Recalculate qty for substitute UOM
        FromFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(SubItem, FinalUOM);
        ToFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(SubItem, SubItem."Base Unit of Measure");
        if ToFactor = 0 then
            ToFactor := 1;

        RequiredQtyBase :=
            RecipeLine."Quantity per Batch" * BatchFactor * (FromFactor / ToFactor);

        // Insert final line
        LITTransferDocLine.Init();
        LITTransferDocLine.Validate("LIT TransferDoc No.", SourceLITTransferDocLine."LIT TransferDoc No.");
        LITTransferDocLine.Validate("LIT TransferDoc Line No.", NewLineNo);
        LITTransferDocLine.Validate("LIT Parent Item", SourceLITTransferDocLine."LIT Item No.");
        LITTransferDocLine.Validate("LIT Parent Line No.", SourceLITTransferDocLine."LIT TransferDoc Line No.");

        LITTransferDocLine.Validate("LIT Item No.", FinalItemNo);
        LITTransferDocLine.Validate("LIT UOM", FinalUOM);
        LITTransferDocLine.Validate("LIT Raw Meterial", true);
        LITTransferDocLine.Validate("LIT Quantity", RequiredQtyBase);

        LITTransferDocLine.Insert(true);
    end;
}
