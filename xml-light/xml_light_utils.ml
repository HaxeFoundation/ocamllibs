module StringMap = Map.Make(String)

type 'a map = 'a StringMap.t
type 'a mut_map = 'a map ref

let create_map() = ref StringMap.empty

let empty_map() = create_map()

let find_map m k = StringMap.find k (!m)

let set_map m k v = m := StringMap.add k v (!m)

let unset_map m k = m := StringMap.remove k (!m)

let iter_map f m = StringMap.iter f (!m)

let fold_map f m = StringMap.fold f (!m)

let mem_map m k = StringMap.mem k (!m)
