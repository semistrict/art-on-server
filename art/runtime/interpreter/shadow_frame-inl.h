/*
 * Copyright (C) 2018 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef ART_RUNTIME_INTERPRETER_SHADOW_FRAME_INL_H_
#define ART_RUNTIME_INTERPRETER_SHADOW_FRAME_INL_H_

#include "shadow_frame.h"

#include "obj_ptr-inl.h"

namespace art HIDDEN {

template<VerifyObjectFlags kVerifyFlags /*= kDefaultVerifyFlags*/>
inline void ShadowFrame::SetVRegReference(size_t i, ObjPtr<mirror::Object> val)
    REQUIRES_SHARED(Locks::mutator_lock_) {
  DCHECK_LT(i, NumberOfVRegs());
  if (kVerifyFlags & kVerifyWrites) {
    VerifyObject(val);
  }
  ReadBarrier::MaybeAssertToSpaceInvariant(val.Ptr());
  // art-host fork (large heap): the authoritative reference is the native-
  // pointer-width entry in the References() side array. The per-vreg value
  // slot is only 4 bytes, so it cannot hold an 8-byte reference; mirror the
  // 32-bit summary (CompressedReference::AsVRegValue, the low bits) there for
  // fast null checks and the raw-reg-equals-reference consistency check.
  // Writing the full StackReference into &vregs_[i] would overflow the value
  // slot and corrupt the adjacent vreg.
  References()[i].Assign(val);
  vregs_[i] = References()[i].AsVRegValue();
}

}  // namespace art

#endif  // ART_RUNTIME_INTERPRETER_SHADOW_FRAME_INL_H_
