package Git_Changes.Repositories is
   --  True when the Git backend this library drives can be executed. A host
   --  checks this once at startup to fail with a clear message rather than
   --  reporting every later query as a broken repository.
   function Available return Boolean;

   procedure Open
     (Path : String; Item : out Repository; Error : out Error_Info);
end Git_Changes.Repositories;
