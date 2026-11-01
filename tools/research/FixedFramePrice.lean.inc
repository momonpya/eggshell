/-- Charge immutable outer framing once, and only the whole priced data for
each proposal. An empty presentation template cannot stand in for the graph
and source-status rows that appear when its evidence is selected. -/
def packetDataCharge (slices : List TransportSlice) : Nat × Nat :=
  ((slices.map (fun slice => slice.text.length+1)).sum,
   (slices.map (fun slice => slice.text.utf8ByteSize+1)).sum)

def packetFrameCharge (frame : Nat × Nat) (slices : List TransportSlice) : Nat × Nat :=
  let data := packetDataCharge slices
  (frame.1+data.1,frame.2+data.2)

theorem packet_frame_charge_independent (frame : Nat × Nat) (slices : List TransportSlice) :
    ((packetFrameCharge frame slices).1-(packetDataCharge slices).1,
     (packetFrameCharge frame slices).2-(packetDataCharge slices).2) = frame := by
  simp [packetFrameCharge]

theorem packet_data_charge_append (left right : List TransportSlice) :
    packetDataCharge (left ++ right) =
      ((packetDataCharge left).1+(packetDataCharge right).1,
       (packetDataCharge left).2+(packetDataCharge right).2) := by
  simp [packetDataCharge,List.sum_append]

