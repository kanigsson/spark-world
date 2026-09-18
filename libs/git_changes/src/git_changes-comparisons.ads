package Git_Changes.Comparisons is
   function Between_Trees (Old_Tree, New_Tree : String) return Comparison
   renames Git_Changes.Tree_To_Tree;
   function Tree_And_Index (Tree : String) return Comparison
   renames Git_Changes.Tree_To_Index;
   function Index_And_Worktree return Comparison
   renames Git_Changes.Index_To_Worktree;
   function Tree_And_Worktree (Tree : String) return Comparison
   renames Git_Changes.Tree_To_Worktree;
end Git_Changes.Comparisons;
