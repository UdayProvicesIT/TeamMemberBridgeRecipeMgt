codeunit 58500 "Replace Wastage LinesByRecipe"
{
    var
        VisitedRecipes: List of [Code[20]];
        ReplaceMainItemBySubItem: Codeunit "Replace Main Item By Sub. Item";

    [EventSubscriber(ObjectType::Table, Database::"LIT ItemJrnlDoc Line",
        'OnBeforeExplodeAssemblyBOM', '', true, true)]
    local procedure UseRecipeInsteadOfWastageBOM(
        var ParentLine: Record "LIT ItemJrnlDoc Line";
        var NewLineNo: Integer;
        var IsHandled: Boolean)
    var
        RecipeMgmtSetup: Record "Recipe Management Setup";
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        FinalItem: Record Item;
        UnitOfMeasureMgt: Codeunit "Unit of Measure Management";
        RecipeNo: Code[20];
        BatchFactor: Decimal;
        FinalQtyInBase: Decimal;
        BatchSizeInBase: Decimal;
        FromFactor: Decimal;
        ToFactor: Decimal;
        LineNo: Integer;
    begin
        if not RecipeMgmtSetup.Get() then
            exit;

        if not RecipeMgmtSetup."Overwrite Assembly BOMs" then
            exit;

        // Skip child RM lines
        if ParentLine."LIT Parent Item" <> '' then
            exit;

        ParentLine.TestField("LIT Item No.");

        IsHandled := true;

        // Locate recipe
        RecipeNo := FindRecipeForItem(
                        ParentLine."LIT Location Code",
                        ParentLine."LIT Item No.");

        if RecipeNo = '' then
            Error('No active recipe found for %1.', ParentLine."LIT Item No.");

        RecipeHeader.Get(RecipeNo);
        RecipeHeader.TestField("Batch Size");

        FinalItem.Get(RecipeHeader."Final Item No.");

        // Convert batch → base UOM
        FromFactor :=
            UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(FinalItem, RecipeHeader."Batch UOM");
        ToFactor :=
            UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(FinalItem, FinalItem."Base Unit of Measure");
        BatchSizeInBase := RecipeHeader."Batch Size" * (FromFactor / ToFactor);

        // Convert journal qty → base
        FromFactor :=
            UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(FinalItem, ParentLine."LIT Unit of Measure Code");
        FinalQtyInBase := ParentLine."LIT Quantity" * (FromFactor / ToFactor);

        BatchFactor := FinalQtyInBase / BatchSizeInBase;

        DeleteRecipeGeneratedLines(ParentLine);

        Clear(VisitedRecipes);
        VisitedRecipes.Add(RecipeHeader."Recipe No.");

        LineNo := ParentLine."LIT ItemJrnlDoc Line No.";

        // Explosion
        RecipeLine.SetRange("Recipe No.", RecipeHeader."Recipe No.");
        if RecipeLine.FindSet() then
            repeat
                InsertExplodedRecipeLine(
                    ParentLine,
                    RecipeHeader,
                    RecipeLine,
                    BatchFactor,
                    LineNo);
            until RecipeLine.Next() = 0;

        ParentLine."LIT Unit Cost" := 0;
        ParentLine."LIT Total Cost" := 0;
        ParentLine.Modify(true);
    end;



    local procedure FindRecipeForItem(LocationCode: Code[10]; ItemNo: Code[20]): Code[20]
    var
        RecipeHeader: Record "Recipe Header";
        RecipeLocation: Record "Recipe Assigned Location";
    begin
        RecipeLocation.SetRange("Location Code", LocationCode);
        if RecipeLocation.FindSet() then
            repeat
                if RecipeHeader.Get(RecipeLocation."Recipe No.") then
                    if (RecipeHeader.Status = RecipeHeader.Status::Active)
                       and (RecipeHeader."Final Item No." = ItemNo)
                    then
                        exit(RecipeHeader."Recipe No.");
            until RecipeLocation.Next() = 0;

        RecipeHeader.Reset();
        RecipeHeader.SetRange("Final Item No.", ItemNo);
        RecipeHeader.SetRange("Default Recipe", true);
        RecipeHeader.SetRange(Status, RecipeHeader.Status::Active);

        if RecipeHeader.FindFirst() then
            exit(RecipeHeader."Recipe No.");

        exit('');
    end;

    local procedure InsertExplodedRecipeLine(
        ParentLine: Record "LIT ItemJrnlDoc Line";
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        BatchFactor: Decimal;
        var LineNo: Integer)
    var
        Item: Record Item;
        CurrentRecipeHeader: Record "Recipe Header";
        CurrentRecipeLine: Record "Recipe Line";
        UnitOfMeasureMgt: Codeunit "Unit of Measure Management";
        FromFactor: Decimal;
        ToFactor: Decimal;
        ReqBase: Decimal;
        ChildBatchBase: Decimal;
        ChildBatchFactor: Decimal;
    begin
        Item.Get(RecipeLine."Item No.");

        // ATO logic
        if (Item."Replenishment System" = Item."Replenishment System"::Assembly)
           and (Item."Assembly Policy" = Item."Assembly Policy"::"Assemble-to-Order")
        then begin

            CurrentRecipeHeader.SetRange("Final Item No.", Item."No.");
            CurrentRecipeHeader.SetRange("Default Recipe", true);
            CurrentRecipeHeader.SetRange(Status, CurrentRecipeHeader.Status::Active);
            CurrentRecipeHeader.FindFirst();

            if VisitedRecipes.IndexOf(CurrentRecipeHeader."Recipe No.") > 0 then
                Error('Circular recipe reference detected.');

            VisitedRecipes.Add(CurrentRecipeHeader."Recipe No.");

            // Convert required quantity → base
            FromFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, RecipeLine."Unit of Measure Code");
            ToFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure");

            ReqBase :=
                RecipeLine."Quantity per Batch" * BatchFactor * (FromFactor / ToFactor);

            // Child batch size → base
            FromFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, CurrentRecipeHeader."Batch UOM");
            ToFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure");

            ChildBatchBase := CurrentRecipeHeader."Batch Size" * (FromFactor / ToFactor);

            ChildBatchFactor := ReqBase / ChildBatchBase;

            CurrentRecipeLine.SetRange("Recipe No.", CurrentRecipeHeader."Recipe No.");
            if CurrentRecipeLine.FindSet() then
                repeat
                    InsertExplodedRecipeLine(
                        ParentLine,
                        CurrentRecipeHeader,
                        CurrentRecipeLine,
                        ChildBatchFactor,
                        LineNo);
                until CurrentRecipeLine.Next() = 0;

            VisitedRecipes.Remove(CurrentRecipeHeader."Recipe No.");
            exit;
        end;

        // RM or ATS
        LineNo += 10000;
        InsertRecipeRMLine(ParentLine, RecipeLine, LineNo, BatchFactor);
    end;



    local procedure InsertRecipeRMLine(
     ParentLine: Record "LIT ItemJrnlDoc Line";
     RecipeLine: Record "Recipe Line";
     NewLineNo: Integer;
     BatchFactor: Decimal)
    var
        LITLine: Record "LIT ItemJrnlDoc Line";
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

        //Calculate required qty in BASE UOM for MAIN item
        FromFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, RecipeLine."Unit of Measure Code");
        ToFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(Item, Item."Base Unit of Measure");
        if ToFactor = 0 then
            ToFactor := 1;

        RequiredQtyBase := RecipeLine."Quantity per Batch" * BatchFactor * (FromFactor / ToFactor);

        // Resolve substitute
        FinalItemNo :=
            ReplaceMainItemBySubItem.ResolveItemWithSubstitute(
                MainItemNo,
                ParentLine."LIT Location Code",
                RequiredQtyBase);

        SubItem.Get(FinalItemNo);

        // UOM selection
        if FinalItemNo = MainItemNo then
            FinalUOM := RecipeLine."Unit of Measure Code"
        else
            FinalUOM := SubItem."Base Unit of Measure";

        // Recalculate required qty for SUBSTITUTE UOM
        FromFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(SubItem, FinalUOM);
        ToFactor := UnitOfMeasureMgt.GetQtyPerUnitOfMeasure(SubItem, SubItem."Base Unit of Measure");
        if ToFactor = 0 then
            ToFactor := 1;

        RequiredQtyBase := RecipeLine."Quantity per Batch" * BatchFactor * (FromFactor / ToFactor);

        // Insert final wastage line
        LITLine.Init();
        LITLine.Validate("LIT ItemJrnlDoc No.", ParentLine."LIT ItemJrnlDoc No.");
        LITLine.Validate("LIT ItemJrnlDoc Line No.", NewLineNo);
        LITLine.Validate("LIT Parent Item", ParentLine."LIT Item No.");
        LITLine.Validate("LIT Parent Line No.", ParentLine."LIT ItemJrnlDoc Line No.");

        LITLine.Validate("LIT Item No.", FinalItemNo);
        LITLine.Validate("LIT Unit of Measure Code", FinalUOM);
        LITLine.Validate("LIT Raw Material", true);
        LITLine.Validate("LIT Quantity", RequiredQtyBase);

        LITLine.Validate("LIT Unit Cost", SubItem."Unit Cost");
        LITLine."LIT Total Cost" := LITLine."LIT Quantity" * LITLine."LIT Unit Cost";

        LITLine.Insert(true);
    end;




    local procedure DeleteRecipeGeneratedLines(SourceLine: Record "LIT ItemJrnlDoc Line")
    var
        LITLine: Record "LIT ItemJrnlDoc Line";
    begin
        LITLine.SetRange("LIT ItemJrnlDoc No.", SourceLine."LIT ItemJrnlDoc No.");
        LITLine.SetRange("LIT Parent Item", SourceLine."LIT Item No.");
        LITLine.DeleteAll();
    end;

}
