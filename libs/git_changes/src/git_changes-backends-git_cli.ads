package Git_Changes.Backends.Git_CLI is
   procedure Capture
     (Repository : Git_Changes.Repository;
      Comparison : Git_Changes.Comparison;
      Pathspecs  : Pathspec_Array;
      Options    : Capture_Options;
      Changes    : out Change_Set;
      Error      : out Error_Info);
end Git_Changes.Backends.Git_CLI;
