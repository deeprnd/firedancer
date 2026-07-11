$(call add-hdrs,pb_firedancer.h pb_common.h pb_decode.h pb_encode.h pb.h,fd_ballet)

$(OBJDIR)/lib/libfd_ballet.a: $(OBJDIR)/obj/third_party/nanopb/pb_common.o $(OBJDIR)/obj/third_party/nanopb/pb_decode.o $(OBJDIR)/obj/third_party/nanopb/pb_encode.o

$(OBJDIR)/obj/third_party/nanopb/%.o : src/third_party/nanopb/%.c
	@echo -e "CC\t$(notdir $@)"
	$(Q)$(MKDIR) $(dir $@) && \
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
