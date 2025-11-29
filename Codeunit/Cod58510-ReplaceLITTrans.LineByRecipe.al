codeunit 58510 "Replace LIT Trans.LineByRecipe"
{
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
        RecipeAssignedLocation: Record "Recipe Assigned Location";
        Item: Record Item;
        BatchFactor: Decimal;
        FinalItemQty: Decimal;
        LineNo: Integer;
    begin
        // Setup not present or feature disabled
        if not RecipeMgtSetup.Get() then
            exit;
        if not RecipeMgtSetup."Overwrite Assembly BOMs" then
            exit;

        // Only override for Finished Goods parent lines
        if not TransferLine."LIT Finished Goods" then
            exit;

        // Skip standard BOM explosion
        IsHandled := true;

        // --- Select best recipe for this item ---
        TransferLine.TestField("LIT Item No.");
        Item.Get(TransferLine."LIT Item No.");

        SelectedRecipeHeader(TransferLine, RecipeHeader);

        if RecipeHeader."Recipe No." = '' then
            exit;  // No recipe → nothing to explode

        // --- Compute Batch Factor ---
        if RecipeHeader."Batch Size" = 0 then
            Error('Batch size cannot be zero for recipe %1.', RecipeHeader."Recipe No.");

        FinalItemQty := TransferLine."LIT Quantity";
        BatchFactor := FinalItemQty / RecipeHeader."Batch Size";

        // --- Remove old exploded lines ---
        DeleteRecipeGeneratedLines(TransferLine);

        // --- Add raw material lines from Recipe ---
        RecipeLine.SetRange("Recipe No.", RecipeHeader."Recipe No.");

        LineNo := TransferLine."LIT TransferDoc Line No." + 10;

        if RecipeLine.FindSet() then
            repeat
                InsertRecipeLineIntoTransfer(TransferLine, RecipeHeader, RecipeLine, LineNo, BatchFactor);
                LineNo += 10;
            until RecipeLine.Next() = 0;
    end;

    //-----------------------------------------
    local procedure SelectedRecipeHeader(var TransferLine: Record "LIT TransferDoc Line"; var RecipeHeader: Record "Recipe Header")
    var
        SelectedRecipeHeader: Record "Recipe Header";
        RecipeAssignedLocation: Record "Recipe Assigned Location";
    begin
        Clear(RecipeHeader);

        // 1) Check assigned location recipes
        SelectedRecipeHeader.SetRange("Final Item No.", TransferLine."LIT Item No.");

        if SelectedRecipeHeader.FindSet() then
            repeat
                RecipeAssignedLocation.SetRange("Recipe No.", SelectedRecipeHeader."Recipe No.");
                RecipeAssignedLocation.SetRange("Location Code", TransferLine."LIT Transfer-from Code");

                if RecipeAssignedLocation.FindFirst() then begin
                    RecipeHeader.Get(SelectedRecipeHeader."Recipe No.");
                    exit;
                end;
            until SelectedRecipeHeader.Next() = 0;

        // 2) Default Recipe
        SelectedRecipeHeader.Reset();
        SelectedRecipeHeader.SetRange("Final Item No.", TransferLine."LIT Item No.");
        SelectedRecipeHeader.SetRange("Default Recipe", true);
        SelectedRecipeHeader.SetRange(Status, SelectedRecipeHeader.Status::Active);

        if SelectedRecipeHeader.FindFirst() then begin
            RecipeHeader.Get(SelectedRecipeHeader."Recipe No.");
            exit;
        end;

        // 3) Fallback to any recipe
        SelectedRecipeHeader.Reset();
        SelectedRecipeHeader.SetRange("Final Item No.", TransferLine."LIT Item No.");

        if SelectedRecipeHeader.FindFirst() then
            RecipeHeader.Get(SelectedRecipeHeader."Recipe No.");
    end;

    //-----------------------------------------
    local procedure DeleteRecipeGeneratedLines(TransferLine: Record "LIT TransferDoc Line")
    var
        LITItemJrnlDocLine: Record "LIT TransferDoc Line";
    begin
        LITItemJrnlDocLine.SetRange("LIT TransferDoc No.", TransferLine."LIT TransferDoc No.");
        LITItemJrnlDocLine.SetRange("LIT Parent Item", TransferLine."LIT Item No.");
        LITItemJrnlDocLine.SetRange("LIT Parent Line No.", TransferLine."LIT TransferDoc Line No.");

        if LITItemJrnlDocLine.FindSet() then
            LITItemJrnlDocLine.DeleteAll();
    end;

    //-----------------------------------------
    local procedure InsertRecipeLineIntoTransfer(
        TransferLine: Record "LIT TransferDoc Line";
        RecipeHeader: Record "Recipe Header";
        RecipeLine: Record "Recipe Line";
        LITItemJrnlDocLineNo: Integer;
        BatchFactor: Decimal)
    var
        LITItemJrnlDocLine: Record "LIT TransferDoc Line";
        QtyToInsert: Decimal;
    begin
        LITItemJrnlDocLine.Init();
        LITItemJrnlDocLine.Validate("LIT TransferDoc No.", TransferLine."LIT TransferDoc No.");
        LITItemJrnlDocLine.Validate("LIT TransferDoc Line No.", LITItemJrnlDocLineNo);
        LITItemJrnlDocLine.Validate("LIT Parent Item", TransferLine."LIT Item No.");
        LITItemJrnlDocLine.Validate("LIT Parent Line No.", TransferLine."LIT TransferDoc Line No.");

        // Raw material item
        LITItemJrnlDocLine.Validate("LIT Item No.", RecipeLine."Item No.");

        QtyToInsert := RecipeLine."Quantity per Batch" * BatchFactor;
        LITItemJrnlDocLine.Validate("LIT Quantity", QtyToInsert);

        LITItemJrnlDocLine.Validate("LIT Raw Meterial", true);

        // UOM (if stored on recipe)
        if RecipeLine."Unit of Measure Code" <> '' then
            LITItemJrnlDocLine.Validate("LIT UOM", RecipeLine."Unit of Measure Code");

        // Copy parent metadata
        LITItemJrnlDocLine.Validate("LIT Status", TransferLine."LIT Status");
        LITItemJrnlDocLine.Validate("LIT Responsibility Center Ship", TransferLine."LIT Responsibility Center Ship");
        LITItemJrnlDocLine.Validate("LIT Responsibility Center Recv", TransferLine."LIT Responsibility Center Recv");
        LITItemJrnlDocLine.Validate("LIT Transfer-from Code", TransferLine."LIT Transfer-from Code");
        LITItemJrnlDocLine.Validate("LIT Transfer-to Code", TransferLine."LIT Transfer-to Code");

        LITItemJrnlDocLine."LIT Posting Date" := TransferLine."LIT Posting Date";
        LITItemJrnlDocLine."LIT Receipt Date" := TransferLine."LIT Receipt Date";

        LITItemJrnlDocLine.Insert(true);
    end;
}

