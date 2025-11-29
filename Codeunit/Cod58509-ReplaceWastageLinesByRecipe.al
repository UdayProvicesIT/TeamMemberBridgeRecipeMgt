codeunit 58509 "Replace Wastage LinesByRecipe"
{
    [EventSubscriber(ObjectType::Table, Database::"LIT ItemJrnlDoc Line",
        'OnBeforeExplodeAssemblyBOM', '', true, true)]
    local procedure UseRecipeInsteadOfWastageBOM(
        var ParentLine: Record "LIT ItemJrnlDoc Line";
        var NewLineNo: Integer;
        var IsHandled: Boolean)
    var
        RecipeMgtSetup: Record "Recipe Management Setup";
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        RecipeAssignedLocation: Record "Recipe Assigned Location";
        Item: Record Item;
        BatchFactor: Decimal;
        FinalItemQty: Decimal;
        LineNo: Integer;
    begin
        // Setup not found, do nothing
        if not RecipeMgtSetup.Get() then
            exit;

        // Only override if setup = TRUE
        if not RecipeMgtSetup."Overwrite Assembly BOMs" then
            exit;

        // Only override FINISHED GOODS lines 
        if not ParentLine."LIT Finished Goods" then
            exit;

        // Mark event handled → skip Wastage BOM explosion completely
        IsHandled := true;

        // SELECT THE BEST RECIPE
        ParentLine.TestField("LIT Item No.");
        Item.Get(ParentLine."LIT Item No.");

        // Try assigned location first
        RecipeAssignedLocation.SetRange("Location Code", ParentLine."LIT Location Code");
        if RecipeAssignedLocation.FindFirst() then begin
            RecipeHeader.Get(RecipeAssignedLocation."Recipe No.");
            if (RecipeHeader.Status = RecipeHeader.Status::Active) and
               (RecipeHeader."Final Item No." = ParentLine."LIT Item No.") then;
        end else begin
            // Default recipe fallback
            RecipeHeader.Reset();
            RecipeHeader.SetRange("Final Item No.", ParentLine."LIT Item No.");
            RecipeHeader.SetRange("Default Recipe", true);
            RecipeHeader.SetRange(Status, RecipeHeader.Status::Active);
            RecipeHeader.FindFirst();
        end;

        // CALCULATE BATCH FACTOR
        if RecipeHeader."Batch Size" = 0 then
            Error('Batch size cannot be zero for recipe %1.', RecipeHeader."Recipe No.");

        FinalItemQty := ParentLine."LIT Quantity";

        BatchFactor := FinalItemQty / RecipeHeader."Batch Size";

        // DELETE EXPLODED LINES
        DeleteRecipeGeneratedLines(ParentLine);

        // INSERT RECIPE LINES
        RecipeLine.SetRange("Recipe No.", RecipeHeader."Recipe No.");

        LineNo := ParentLine."LIT ItemJrnlDoc Line No." + 10000;

        if RecipeLine.FindSet() then
            repeat
                InsertRecipeLineIntoWastage(ParentLine, RecipeHeader, RecipeLine, LineNo, BatchFactor);
                LineNo += 10000;
            until RecipeLine.Next() = 0;
    end;

    // DELETE OLD RAW-MATERIAL LINES
    local procedure DeleteRecipeGeneratedLines(ParentLine: Record "LIT ItemJrnlDoc Line")
    var
        LITItemJrnlDocLine: Record "LIT ItemJrnlDoc Line";
    begin
        LITItemJrnlDocLine.SetRange("LIT ItemJrnlDoc No.", ParentLine."LIT ItemJrnlDoc No.");
        LITItemJrnlDocLine.SetRange("LIT Parent Item", ParentLine."LIT Item No.");
        LITItemJrnlDocLine.DeleteAll();
    end;

    // INSERT NEW LINES FROM RECIPE
    local procedure InsertRecipeLineIntoWastage(
        LITItemJrnlDocLine: Record "LIT ItemJrnlDoc Line";
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        LITItemJrnlDocLineNo: Integer;
        BatchFactor: Decimal)
    var
        NewLITItemJrnlDocLine: Record "LIT ItemJrnlDoc Line";
    begin
        NewLITItemJrnlDocLine.Init();
        NewLITItemJrnlDocLine.Validate("LIT ItemJrnlDoc No.", LITItemJrnlDocLine."LIT ItemJrnlDoc No.");
        NewLITItemJrnlDocLine.Validate("LIT ItemJrnlDoc Line No.", LITItemJrnlDocLineNo);
        NewLITItemJrnlDocLine.Validate("LIT Parent Item", LITItemJrnlDocLine."LIT Item No.");
        NewLITItemJrnlDocLine.Validate("LIT Parent Line No.", LITItemJrnlDocLine."LIT ItemJrnlDoc Line No.");

        NewLITItemJrnlDocLine.Validate("LIT Item No.", RecipeLine."Item No.");
        NewLITItemJrnlDocLine.Validate("LIT Quantity", RecipeLine."Quantity per Batch" * BatchFactor);
        NewLITItemJrnlDocLine.Validate("LIT Raw Material", true);

        NewLITItemJrnlDocLine.Insert(true);
    end;
}


