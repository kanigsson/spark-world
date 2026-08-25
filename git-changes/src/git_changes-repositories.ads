package Git_Changes.Repositories is
   procedure Open
     (Path  : String;
      Item  : out Repository;
      Error : out Error_Info);
end Git_Changes.Repositories;
