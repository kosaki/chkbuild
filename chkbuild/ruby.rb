require 'chkbuild'

module ChkBuild
  module Ruby
    METHOD_LIST_SCRIPT = <<'End'
nummodule = nummethod = 0
mods = []
ObjectSpace.each_object(Module) {|m| mods << m }
mods = mods.sort_by {|m| m.name }
mods.each {|mod|
  nummodule += 1
  puts "#{mod.name} #{(mod.ancestors - [mod]).inspect}"
  mod.singleton_methods(false).sort.each {|methname|
    nummethod += 1
    meth = mod.method(methname)
    puts "#{mod.name}.#{methname} #{meth.arity}"
  }
  mod.instance_methods(false).sort.each {|methname|
    nummethod += 1
    meth = mod.instance_method(methname)
    puts "#{mod.name}\##{methname} #{meth.arity}"
  }
}
puts "#{nummodule} modules, #{nummethod} methods"
End

    # not strictly RFC 1034.
    DOMAINLABEL = /[A-Za-z0-9-]+/
    DOMAINPAT = /#{DOMAINLABEL}(\.#{DOMAINLABEL})*/

    module_function
    def def_target(*args)
      opts = Hash === args.last ? args.pop : {}
      default_opts = {:separated_srcdir=>false}
      opts = default_opts.merge(opts)
      args.push opts
      opts = Hash === args.last ? args.last : {}
      separated_srcdir = opts[:separated_srcdir]
      t = ChkBuild.def_target("ruby", *args) {|b, *suffixes|
        ruby_build_dir = b.build_dir

        ruby_branch = nil
        configure_flags = []
        cflags = %w{-Wall -Wformat=2 -Wno-parentheses -g -O2 -DRUBY_GC_STRESS}
        gcc_dir = nil
        autoconf_command = 'autoconf'
        make_options = {}
        suffixes.each {|s|
          case s
          when "trunk" then ruby_branch = nil
          when "1.8" then ruby_branch = 'ruby_1_8'
          when "yarv" then ruby_branch = 'yarv'
          when "o0"
            cflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
            cflags << '-O0'
          when "o1"
            cflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
            cflags << '-O1'
          when "o3"
            cflags.delete_if {|arg| /\A-O\d\z/ =~ arg }
            cflags << '-O3'
          when "pth" then configure_flags << '--enable-pthread'
          when /\Agcc=/
            configure_flags << "CC=#{$'}/bin/gcc"
            make_options["ENV:LD_RUN_PATH"] = "#{$'}/lib"
          when /\Aautoconf=/
            autoconf_command = "#{$'}/bin/autoconf"
          else
            raise "unexpected suffix: #{s.inspect}"
          end
        }

        objdir = ruby_build_dir+'ruby'
        if separated_srcdir
          checkout_dir = ruby_build_dir.dirname
        else
          checkout_dir = ruby_build_dir
        end
        srcdir = (checkout_dir+'ruby').relative_path_from(objdir)

        Dir.chdir(checkout_dir)
        if ruby_branch == 'yarv'
          b.svn("http://www.atdot.net/svn/yarv", "trunk", 'ruby',
            :viewcvs=>'http://www.atdot.net/viewcvs/yarv?diff_format=u')
        else
          b.cvs(
            ":pserver:anonymous@cvs.ruby-lang.org:/src", "ruby", ruby_branch,
            :cvsweb => "http://www.ruby-lang.org/cgi-bin/cvsweb.cgi")
        end
        Dir.chdir("ruby")
        b.run(autoconf_command)

        Dir.chdir(ruby_build_dir)
        b.mkcd("ruby")
        b.run("#{srcdir}/configure", "--prefix=#{ruby_build_dir}", "CFLAGS=#{cflags.join(' ')}", *configure_flags)
        b.make("miniruby", make_options)
        b.catch_error { b.run("./miniruby", "-v", :section=>"version") }
        b.catch_error { b.run("./miniruby", "#{srcdir+'sample/test.rb'}", :section=>"test.rb") }
        b.catch_error { b.run("./miniruby", '-e', METHOD_LIST_SCRIPT, :section=>"method-list") }
        b.make(make_options)
        b.make("install")
        b.catch_error { b.run("./ruby", "#{srcdir+'test/runner.rb'}", "-v", :section=>"test-all") }
      }

      t.add_title_hook("configure") {|title, log|
        if /^checking target system type\.\.\. (\S+)$/ =~ log
          title.update_title(:version, "#{title.suffixed_name} [#{$1}]")
        end
      }

      t.add_title_hook("version") {|title, log|
        if /^ruby [0-9.]+ \([0-9\-]+\) \[\S+\]$/ =~ log
          ver = $&
          ss = title.suffixed_name.split(/-/)[1..-1].reject {|s| /\A(trunk|1\.8|yarv)\z/ =~ s }
          ver << " [#{ss.join(',')}]" if !ss.empty?
          title.update_title(:version, ver)
        end
      }
        
      t.add_failure_hook("test.rb") {|log|
        if /^end of test/ !~ log
          if /^test: \d+ failed (\d+)/ =~ log
            "#{$1}NotOK"
          end
        end
      }

      t.add_failure_hook("test-all") {|log|
        if /^\d+ tests, \d+ assertions, (\d+) failures, (\d+) errors$/ =~ log
          failures = $1.to_i
          errors = $2.to_i
          if failures != 0 || errors != 0
            "#{failures}F#{errors}E"
          end
        end
      }

      t.add_title_hook(nil) {|title, log|
        mark = ''
        mark << "[BUG]" if /\[BUG\]/i =~ log
        mark << "[SEGV]" if /segmentation fault|signal segv/i =~
          log.sub(/combination may cause frequent hang or segmentation fault/, '') # skip tk message.
        mark << "[FATAL]" if /\[FATAL\]/i =~ log
        title.update_title(:mark, mark)
      }

      t.add_diff_preprocess_gsub(/^ *\d+\) (Error:|Failure:)/) {|match|
        " <n>) #{match[1]}"
      }

      t.add_diff_preprocess_gsub(%r{\(druby://(#{DOMAINPAT}):\d+\)}o) {|match|
        "(druby://#{match[1]}:<port>)"
      }

      t.add_diff_preprocess_gsub(/^Elapsed: [0-9.]+s/) {|match|
        "Elapsed: <t>s"
      }

      t.add_diff_preprocess_gsub(/^Finished in [0-9.]+ seconds\./) {|match|
        "Finished in <t> seconds."
      }

      t
    end
  end
end
